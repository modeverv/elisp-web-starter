;;; react.el --- A small React in Emacs Lisp  -*- lexical-binding: t; -*-

;; Copyright (c) 2026 modeverv
;; SPDX-License-Identifier: MIT

;; An experiment: can the React of 2013 (components with props and state,
;; render functions that return a virtual DOM, reconciliation) be written in
;; Emacs Lisp, with the browser's DOM as the output?
;;
;; Everything that is React lives here: elements, components, state, the
;; reconciler that compares the previous tree with the new one.  This file
;; never touches a DOM.  It produces a list of small DOM operations
;; ("create a div", "set this text", "insert that node here") which a thin
;; JavaScript host (js/elisp-react.js) applies, and it receives the DOM's
;; events from that host.  Emacs itself runs in the page as WebAssembly
;; (the wasmacs eval service).

;;; Elements
;;
;; A virtual DOM is plain Lisp data:
;;
;;   "text", 42                          a text node
;;   (div (:class "box") CHILD...)       a DOM element: (TAG PROPS CHILD...)
;;   (div CHILD...)                      PROPS may be left out
;;   (counter (:start 3))                a component, defined with
;;                                       `react-define-component'
;;   (<> CHILD...)                       a fragment: its children, without
;;                                       an element around them (JSX's <>)
;;
;; PROPS is a plist with keyword keys.  For a DOM element:
;;
;;   :on-click FUNCTION    an event listener; FUNCTION gets the event, a
;;                         plist (:type "click" :value :checked :key :code
;;                         :alt :ctrl :meta :shift :repeat :composing :button
;;                         :x :y :target, :files [(:name :size :type)] for a
;;                         file input, :form [[NAME VALUE]...] for a submit)
;;   :value :checked       DOM properties (controlled inputs)
;;   :style                a string, or a plist (:color "red" :margin-top "4px")
;;   :inner-html           HTML text from elsewhere, which the page cleans
;;                         (no scripts, handlers or script URLs); the element
;;                         then has no children of its own
;;   :key                  not rendered; identifies a child among its
;;                         siblings (see below)
;;   :ref                  not rendered; a name under which the component
;;                         that rendered the element finds its DOM node
;;                         (`react-focus', `react-invoke')
;;   anything else         an attribute; nil removes it, t sets it empty
;;
;; Among the children, nil is skipped and a list of elements (what `mapcar'
;; returns) is spliced in.  Backquote does the rest:
;;
;;   `(ul () ,@(mapcar (lambda (item) `(li () ,item)) items))
;;
;; or the `jsx' macro, which needs no commas:
;;
;;   (jsx (ul (mapcar (lambda (item) (jsx (li item))) items)))
;;
;; Children of a list that changes (rows that are added, removed, sorted)
;; get a :key each: (li (:key ID) ...).  On the next render a child with the
;; same key is the same child: it keeps its DOM node and its components keep
;; their state, wherever it now stands.  Without keys children are matched
;; by position.
;;
;; A fragment puts its children where it stands, among its parent's
;; children: a component can render two table rows, a <dt> and its <dd>,
;; or the items of a grid.  It takes no props but :key, and a component
;; that renders a list of elements renders a fragment of them:
;;
;;   (jsx (<> (tr (td name)) (when open (jsx (tr (td details))))))

;;; Components
;;
;;   (react-define-component 'counter
;;     :initial-state (lambda (props) (list :count (or (plist-get props :start) 0)))
;;     :render (lambda (self)
;;               `(button (:on-click ,(lambda (_event)
;;                                      (react-set-state self :count (1+ (react-state self :count)))))
;;                  ,(format "%d" (react-state self :count)))))
;;
;;   (react-mount '(counter (:start 3)) "#app")
;;
;; State is a plist.  `react-set-state' never modifies it: it installs a new
;; plist and schedules the component to render again.

;;; The page, and time
;;
;; Lisp runs only while it answers the host: it cannot wait, and it cannot
;; reach into the page.  What a component wants from the page is therefore
;; data too, sent along with the DOM operations; the host does it, and when
;; there is an answer it calls Lisp again, which runs the function that was
;; waiting for it:
;;
;;   (react-set-timeout 1000 (lambda () ...))      also `react-set-interval'
;;   (react-fetch "/data.json" :then (lambda (response) ...))
;;   (react-storage-set "todos" todos)             localStorage, any Lisp data
;;   (react-focus self "edit")                     the element with :ref "edit"
;;
;; Such a function typically ends in `react-set-state'.  Start timers and
;; requests in :did-mount, react to a finished render in :did-update, stop
;; timers in :will-unmount.
;;
;; `react-async' writes the same thing top to bottom: the code stops at each
;; `react-await' and goes on when the page has answered.
;;
;;   (react-async
;;     (react-set-state self :status 'loading)
;;     (let ((response (react-await (react-fetch-async "/data.json"))))
;;       (react-await (react-sleep 300))
;;       (react-set-state self :status 'loaded :data (react-response-json response))))

;;; Code:

(require 'cl-lib)
(require 'generator)

;;;; Mounted tree

;; What is on the page, as the reconciler remembers it.

(cl-defstruct (react--text (:constructor react--text-create))
  dom-id text)

(cl-defstruct (react--host (:constructor react--host-create))
  dom-id tag props children
  owner       ; the component instance whose render produced it
  svg)        ; its children are SVG elements

(cl-defstruct (react--fragment (:constructor react--fragment-create))
  props       ; (:key KEY) or nil
  children    ; mounted; their nodes are siblings in the parent's node
  anchor)     ; the DOM id of an empty text node after them: where the
              ; fragment is, also when it has no children

(cl-defstruct (react--instance (:constructor react--instance-create))
  type        ; the component's name
  spec        ; its definition (plist)
  props state
  child       ; what it rendered, mounted
  depth       ; components between the root and this one
  dirty       ; state changed since the last render
  mounted     ; nil once unmounted
  rendered-props rendered-state   ; what the last render saw
  refs        ; alist: ref name -> mounted element
  force       ; render even if :should-update says no (the definition changed)
  parent      ; the component instance whose render produced it, or nil
  readers     ; for a context provider: the instances that read it
  effects     ; alist: effect key -> (DEPS . CLEANUP), see `react-effect'
  svg)        ; it renders inside an <svg>

(defconst react--protocol 3
  "The version of the operations and commands between this file and
js/elisp-react.js.  The host refuses a react.el of another version.")

(defvar react--next-dom-id 0)
(defvar react--ops nil "DOM operations for the host, newest first.")
(defvar react--hosts (make-hash-table) "DOM id -> mounted element.")
(defvar react--roots (make-hash-table :test #'equal) "Selector -> mounted root.")
(defvar react--dirty nil "Component instances that have to render again.")
(defvar react--did-mount nil "Instances mounted since the last flush.")
(defvar react--did-update nil "(INSTANCE PREVIOUS-PROPS PREVIOUS-STATE) of renders since the last flush.")
(defvar react--owner nil "The component instance that is rendering.")
(defvar react--svg nil "Non-nil while mounting inside an <svg> (elements in the SVG namespace).")
(defvar react--effects nil "(INSTANCE KEY DEPS FUNCTION) to run after the renders, newest first.")
(defvar react--next-request 0)
(defvar react--requests (make-hash-table) "Request id -> (FUNCTION . KEEP) waiting for the host.")
(defvar react--storage (make-hash-table :test #'equal) "localStorage of this page: key -> printed value.")

(defun react--emit (&rest op)
  (push (vconcat (mapcar #'react--valid-data op)) react--ops))

;; The operations go to the page as JSON, which carries Unicode text only.
;; An Emacs string can hold bytes (`json-serialize' returns UTF-8 bytes,
;; `url-unhex-string' raw ones): one of them in an operation used to make
;; the whole answer unsendable, and every DOM change of that event was lost.

(defconst react--invalid-text (rx (any (#xD800 . #xDFFF) (#x3FFF80 . #x3FFFFF)))
  "Characters that are not Unicode: surrogates and raw bytes.")

(defvar react--warned-invalid nil "Components already warned about invalid text.")

(defun react--valid-text (string)
  "STRING as Unicode text: bytes are read as UTF-8, and what is still not
text becomes U+FFFD (with a warning, once per component)."
  (when (and (not (multibyte-string-p string)) (string-match-p "[\200-\377]" string))
    (setq string (decode-coding-string string 'utf-8 t)))
  (if (not (and (multibyte-string-p string) (string-match-p react--invalid-text string)))
      string
    (let ((who (and react--owner (react--instance-type react--owner))))
      (unless (memq who react--warned-invalid)
        (push who react--warned-invalid)
        (message "react: %s gave the page text that is not Unicode (bytes?); it shows as U+FFFD: %S"
                 (or who "Lisp") string)))
    (replace-regexp-in-string react--invalid-text "\uFFFD" string t t)))

(defun react--valid-data (data)
  "DATA (an operation's argument) with every string in it valid text."
  (cond ((stringp data) (react--valid-text data))
        ((vectorp data) (vconcat (mapcar #'react--valid-data data)))
        ((consp data) (cons (react--valid-data (car data)) (react--valid-data (cdr data))))
        (t data)))

(defun react--new-dom-id ()
  (cl-incf react--next-dom-id))

(defun react--dom-id (mounted)
  "The id of the first DOM node that MOUNTED is on the page."
  (cond ((react--text-p mounted) (react--text-dom-id mounted))
        ((react--host-p mounted) (react--host-dom-id mounted))
        ((react--fragment-p mounted)
         (let ((children (react--fragment-children mounted)))
           (if children (react--dom-id (car children)) (react--fragment-anchor mounted))))
        (t (react--dom-id (react--instance-child mounted)))))

(defun react--nodes (mounted)
  "The ids of the DOM nodes that MOUNTED is on the page, in order: one,
or for a fragment the nodes of its children and then its anchor."
  (cond ((react--text-p mounted) (list (react--text-dom-id mounted)))
        ((react--host-p mounted) (list (react--host-dom-id mounted)))
        ((react--fragment-p mounted)
         (nconc (mapcan #'react--nodes (react--fragment-children mounted))
                (list (react--fragment-anchor mounted))))
        (t (react--nodes (react--instance-child mounted)))))

(defun react--place (parent-id mounted before)
  "Put the DOM nodes of MOUNTED in front of the node BEFORE.
In the node PARENT-ID, at its end when BEFORE is nil; without PARENT-ID
\(a fragment's children) next to BEFORE, wherever that is."
  (dolist (id (react--nodes mounted))
    (if parent-id
        (react--emit "insert" parent-id id before)
      (react--emit "before" id before))))

(defun react--take-off (mounted)
  "Take the DOM nodes of MOUNTED off the page."
  (dolist (id (react--nodes mounted)) (react--emit "remove" id)))

(defun react--replace (old new)
  "Put the DOM nodes of NEW where those of OLD are, and take those off."
  (let ((old-nodes (react--nodes old))
        (new-nodes (react--nodes new)))
    (if (and (null (cdr old-nodes)) (null (cdr new-nodes)))
        (react--emit "replace" (car old-nodes) (car new-nodes))
      (dolist (id new-nodes) (react--emit "before" id (car old-nodes)))
      (dolist (id old-nodes) (react--emit "remove" id)))))

;;;; Elements

(defun react-define-component (name &rest spec)
  "Define the component NAME (a symbol).  SPEC is a plist:

:render FUNCTION         (SELF) -> an element.  Required.
:initial-state FUNCTION  (PROPS) -> the first state, a plist.
:did-mount FUNCTION      (SELF), after the component is on the page.
:did-update FUNCTION     (SELF PREVIOUS-PROPS PREVIOUS-STATE), after each
                         later render.
                         (These two and :will-unmount also take a list of
                         functions, called in order: helpers can each add
                         one.  See also `react-effect'.)
:should-update FUNCTION  (SELF PREVIOUS-PROPS PREVIOUS-STATE) -> nil to skip
                         a render: the component and everything below it
                         stay as they are.  PREVIOUS-PROPS and
                         PREVIOUS-STATE are what the last render saw; SELF
                         has the new ones.  See `react-changed-p'.
:pure t                  Shorthand: render only when a prop or the state
                         changed (`react-shallow-equal').
:will-unmount FUNCTION   (SELF), before it is taken off.
:did-catch FUNCTION      (SELF ERROR): a component below failed to render.
                         That component renders nothing; SELF typically
                         sets state to render something else instead (an
                         error boundary).

An element (NAME PROPS CHILD...) then renders this component.  Its
children reach the component as the prop :children."
  (declare (indent 1))
  (unless (functionp (plist-get spec :render))
    (error "Component %s has no :render function" name))
  (when (and (plist-get spec :pure) (not (plist-get spec :should-update)))
    (setq spec (append spec (list :should-update #'react--pure-should-update))))
  (let ((defined (get name 'react-component)))
    (put name 'react-component spec)
    ;; Defined again while it is on the page (a development tool evaluated
    ;; the changed source): the instances take the new definition and render
    ;; again with the state they have.
    (when defined (react--redefined name spec)))
  name)

(defun react--redefined (name spec)
  "Give the mounted instances of the component NAME its new SPEC."
  (react--each-instance
   (lambda (instance)
     (when (eq (react--instance-type instance) name)
       (setf (react--instance-spec instance) spec)
       (react--force-render instance)))))

(defun react--force-render (instance)
  "Have INSTANCE render again at the next flush, whatever :should-update says."
  (when (react--instance-mounted instance)
    (setf (react--instance-force instance) t
          (react--instance-dirty instance) t)
    (unless (memq instance react--dirty) (push instance react--dirty))))

(defun react--each-instance (function &optional mounted)
  "Call FUNCTION with every component instance below MOUNTED (or on the page)."
  (cond ((null mounted) (maphash (lambda (_selector root) (react--each-instance function root)) react--roots))
        ((react--instance-p mounted)
         (funcall function mounted)
         (react--each-instance function (react--instance-child mounted)))
        ((react--host-p mounted)
         (dolist (child (react--host-children mounted)) (react--each-instance function child)))
        ((react--fragment-p mounted)
         (dolist (child (react--fragment-children mounted)) (react--each-instance function child)))))

(defun react--element-props (element)
  "The props of ELEMENT, which is (TAG [PROPS] CHILD...)."
  (let ((second (cadr element)))
    (and (consp second) (keywordp (car second)) second)))

(defun react--element-children (element)
  "The children of ELEMENT: nil dropped, lists of elements spliced in."
  (let ((rest (cdr element)))
    (when (and rest (or (null (car rest)) (and (consp (car rest)) (keywordp (caar rest)))))
      (setq rest (cdr rest)))
    (react--flatten-children rest)))

(defun react--flatten-children (children)
  (let (out)
    (dolist (child children)
      (cond ((or (null child) (eq child t)))
            ;; A list of elements: what `mapcar' returns, nil items too
            ;; (`when' in the mapped function), the first one included.
            ((and (consp child) (or (null (car child)) (not (symbolp (car child)))))
             (setq out (nconc (nreverse (react--flatten-children child)) out)))
            (t (push child out))))
    (nreverse out)))

(defun react--kind (vnode)
  "What VNODE renders as: `text', `fragment', (host . TAG) or (component . NAME)."
  (cond ((or (stringp vnode) (numberp vnode)) 'text)
        ((and (consp vnode) (eq (car vnode) '<>)) 'fragment)
        ((and (consp vnode) (car vnode) (symbolp (car vnode)))
         (cons (if (get (car vnode) 'react-component) 'component 'host) (car vnode)))
        (t (error "Not an element: %S" vnode))))

(defun react--text-of (vnode)
  (if (stringp vnode) vnode (format "%s" vnode)))

;;;; jsx

(defconst react-html-tags
  '(a abbr address area article aside audio b bdi bdo blockquote body br button canvas caption
    cite code col colgroup data datalist dd del details dfn dialog div dl dt em embed fieldset
    figcaption figure footer form h1 h2 h3 h4 h5 h6 head header hgroup hr html i iframe img
    input ins kbd label legend li link main map mark menu meta meter nav noscript object ol
    optgroup option output p picture pre progress q rp rt ruby s samp script search section
    select slot small source span strong style sub summary sup table tbody td template
    textarea tfoot th thead time title tr track u ul var video wbr)
  "The HTML elements that `jsx' recognises.")

(defconst react-svg-tags
  '(svg g defs symbol use path circle ellipse line polyline polygon rect text tspan textPath
    linearGradient radialGradient stop clipPath mask pattern marker image foreignObject
    animate animateMotion animateTransform desc filter feBlend feColorMatrix
    feComposite feFlood feGaussianBlur feMerge feMergeNode feOffset feDropShadow)
  "The SVG elements that `jsx' recognises (not `set', a Lisp function:
write that one with backquote).  Inside an <svg> every element is created
as SVG.")

;; Markup indents like a special form with one distinguished argument, the
;; props: (div (:class "x")
;;           (p "child"))
(dolist (tag (cons '<> (append react-html-tags react-svg-tags)))
  (unless (get tag 'lisp-indent-function)
    (put tag 'lisp-indent-function 1)))

(defun react--jsx-element-p (form)
  "Non-nil if FORM is markup for `jsx': (TAG ...) or (Component ...)."
  (and (consp form) (symbolp (car form)) (car form)
       (or (eq (car form) '<>)
           (memq (car form) react-html-tags)
           (memq (car form) react-svg-tags)
           (let ((first (aref (symbol-name (car form)) 0)))
             (and (<= ?A first) (<= first ?Z))))))

(defun react--jsx (form)
  "The Lisp expression that builds the element which FORM describes."
  (if (not (react--jsx-element-p form))
      form
    (let* ((rest (cdr form))
           (has-props (and rest (or (null (car rest)) (and (consp (car rest)) (keywordp (caar rest))))))
           (props (and has-props (car rest)))
           (children (if has-props (cdr rest) rest))
           prop-forms)
      (while props
        (unless (keywordp (car props)) (error "jsx: %S is not a prop name in %S" (car props) form))
        (push (car props) prop-forms)
        (push (react--jsx (cadr props)) prop-forms)
        (setq props (cddr props)))
      `(list ',(car form)
             ,(and prop-forms `(list ,@(nreverse prop-forms)))
             ,@(mapcar #'react--jsx children)))))

(defmacro react-jsx (form)
  "Build an element from markup, without backquote and commas.

  (jsx (div (:class \"counter\")
         (p (format \"Count: %d\" count))
         (button (:on-click (lambda (_event) (increment))) \"+1\")
         (when (> count 9) (jsx (strong \"a lot\")))
         (Badge (:text label))))

FORM and everything in it is read like this:

- A list that starts with an HTML tag (`react-html-tags') or with a
  Capitalized symbol is an element: (TAG PROPS CHILD...) or (TAG CHILD...).
  Capitalized names are components, as in JSX; <> is a fragment, its
  children without an element around them.  The prop names are taken
  as they are; the prop values and the children are read by these rules.
- Anything else is Lisp and is evaluated: a variable, a string, a call
  like (format ...) or (mapcar ...).  Its value may be an element, a list
  of elements, text or nil.  Markup inside such Lisp needs `jsx' again.

The value is the same plain list a backquote would build."
  (unless (react--jsx-element-p form)
    (error "jsx: %S does not start with an HTML tag, a Capitalized component name or <>" form))
  (react--jsx form))

(defalias 'jsx #'react-jsx)

;;;; DOM element props

(cl-defstruct (react-handler (:constructor react--handler-create) (:copier nil))
  function options)

(defun react-handler (function &rest options)
  "A listener prop that the page acts on before Lisp answers.
FUNCTION gets the event, as a plain function prop would.  OPTIONS:

:keys LIST     only events of these keys (\"Enter\" \"/\")
:self t        only events of this element, not of its children
:prevent t     preventDefault: the browser does not follow the link,
               type the key, submit, scroll ...
:stop t        stopPropagation: listeners of the parents do not hear it
:capture t     hear it on the way down, before the children
:passive t     tell the browser it will not be prevented (smooth scroll)
:throttle MS   at most one event per MS milliseconds; the last of a
               burst is not lost

  (input (:on-keydown
          (react-handler #\='submit-search :keys \='(\"Enter\") :prevent t)))"
  (react--handler-create :function function :options options))

(defun react--listener-function (value)
  (if (react-handler-p value) (react-handler-function value) value))

(defun react--listener-options (value)
  "The options of the listener prop VALUE for the host, or nil."
  (when (react-handler-p value)
    (let ((options (react-handler-options value)) out)
      (while options
        (let ((key (car options)) (option (cadr options)))
          (when (memq key '(:keys :self :prevent :stop :capture :passive :throttle))
            (setq out (plist-put out key (cond ((eq key :keys) (vconcat option))
                                               ((eq key :throttle) option)
                                               (t (and option t)))))))
        (setq options (cddr options)))
      out)))

(defun react--event-name (key)
  "\"click\" for :on-click; nil when KEY is not a listener prop."
  (let ((name (symbol-name key)))
    (and (string-prefix-p ":on-" name) (substring name 4))))

(defconst react--unitless-styles
  '("opacity" "z-index" "flex" "flex-grow" "flex-shrink" "order" "font-weight" "line-height"
    "zoom" "column-count" "orphans" "widows" "tab-size" "fill-opacity" "stroke-opacity"
    "stroke-miterlimit" "flood-opacity" "stop-opacity" "animation-iteration-count"
    "grid-row" "grid-column" "grid-row-start" "grid-row-end" "grid-column-start" "grid-column-end"
    "aspect-ratio" "scale")
  "CSS properties whose numbers have no unit; other numbers in a :style
plist are pixels.")

(defun react--style-string (style)
  (if (stringp style)
      style
    (let (parts)
      (while style
        (let* ((name (substring (symbol-name (car style)) 1))
               (value (cadr style)))
          (when value
            (push (format "%s: %s" name
                          (if (and (numberp value) (not (zerop value))
                                   (not (member name react--unitless-styles))
                                   (not (string-prefix-p "--" name)))
                              (format "%spx" value)
                            value))
                  parts)))
        (setq style (cddr style)))
      (mapconcat #'identity (nreverse parts) "; "))))

(defun react--attribute-value (key value)
  "VALUE of the prop KEY as an attribute: a string, t (present) or nil (absent).
A list of classes is joined; t and :false of an ARIA attribute are
\"true\" and \"false\"."
  (let ((aria (string-prefix-p ":aria-" (symbol-name key))))
    (cond ((null value) nil)
          ((and aria (eq value t)) "true")
          ((and aria (eq value :false)) "false")
          ((eq value :false) nil)
          ((eq value t) t)
          ((eq key :style) (react--style-string value))
          ((and (eq key :class) (listp value))
           (mapconcat #'identity (delq nil (mapcar (lambda (each) (and each (format "%s" each))) value)) " "))
          ((stringp value) value)
          (t (format "%s" value)))))

(defun react--set-prop (dom-id key value)
  "Put the prop KEY with VALUE on the DOM node DOM-ID."
  (cond ((memq key '(:key :ref)))
        ((react--event-name key)
         (if value
             (react--emit "listen" dom-id (react--event-name key) (react--listener-options value))
           (react--emit "unlisten" dom-id (react--event-name key))))
        ((eq key :inner-html)
         (react--emit "html" dom-id (or value "")))
        ((memq key '(:value :checked))
         (react--emit "prop" dom-id (substring (symbol-name key) 1)
                      (if (eq key :checked) (and value (not (eq value :false)) t) (react--text-of (or value "")))))
        (t (react--emit "attr" dom-id (substring (symbol-name key) 1)
                        (react--attribute-value key value)))))

(defun react--update-props (dom-id old new)
  "Change the DOM node DOM-ID from the props OLD to the props NEW."
  (let ((plist new))
    (while plist
      (let ((key (car plist)) (value (cadr plist)))
        (cond ((memq key '(:key :ref)))
              ((react--event-name key)
               ;; Only whether there is a listener, and its options, matter
               ;; to the DOM; the function is looked up when the event arrives.
               (unless (and (eq (null value) (null (plist-get old key)))
                            (equal (react--listener-options value) (react--listener-options (plist-get old key))))
                 (react--set-prop dom-id key value)))
              ;; What the user typed is not in OLD: say it again.
              ((memq key '(:value :checked)) (react--set-prop dom-id key value))
              ((not (equal value (plist-get old key))) (react--set-prop dom-id key value))))
      (setq plist (cddr plist))))
  (let ((plist old))
    (while plist
      (unless (plist-member new (car plist))
        (react--set-prop dom-id (car plist) nil))
      (setq plist (cddr plist)))))

;;;; Mounting

(define-error 'react-render-error "Error while rendering")

(defun react--render (instance)
  "Call INSTANCE's render function; the result is one element (a list
of elements is a fragment of them).
An error in it is caught by the nearest component above with :did-catch,
and INSTANCE then renders nothing; without one, it is signalled again as
`react-render-error', which says which component it came from."
  (condition-case err
      (let ((vnode (funcall (plist-get (react--instance-spec instance) :render) instance)))
        (cond ((null vnode) "")
              ((and (consp vnode) (or (null (car vnode)) (not (symbolp (car vnode)))))
               (cons '<> vnode))
              (t vnode)))
    (error
     (let ((boundary (react--boundary instance)))
       (cond (boundary
              (funcall (plist-get (react--instance-spec boundary) :did-catch) boundary err)
              "")
             ((eq (car err) 'react-render-error) (signal (car err) (cdr err)))
             (t (signal 'react-render-error
                        (list (format "%s, in %s" (error-message-string err) (react--component-path instance))))))))))

(defun react--boundary (instance)
  "The nearest component above INSTANCE that has :did-catch, or nil."
  (let ((ancestor (react--instance-parent instance)))
    (while (and ancestor (not (plist-get (react--instance-spec ancestor) :did-catch)))
      (setq ancestor (react--instance-parent ancestor)))
    ancestor))

(defun react--component-path (instance)
  "\"Card < Page < App\": INSTANCE and the components above it."
  (let (names)
    (while instance
      (push (symbol-name (react--instance-type instance)) names)
      (setq instance (react--instance-parent instance)))
    (mapconcat #'identity (nreverse names) " < ")))

(defun react--mount (vnode depth)
  "Create VNODE (DOM operations and bookkeeping).  Returns it mounted."
  (pcase (react--kind vnode)
    ('text
     (let ((mounted (react--text-create :dom-id (react--new-dom-id) :text (react--text-of vnode))))
       (react--emit "text" (react--text-dom-id mounted) (react--text-text mounted))
       mounted))
    (`(host . ,tag)
     (let* ((id (react--new-dom-id))
            (props (react--element-props vnode))
            (svg (or (eq tag 'svg) react--svg))
            ;; In <foreignObject> the children are HTML again.
            (react--svg (and svg (not (eq tag 'foreignObject))))
            (mounted (react--host-create :dom-id id :tag tag :props props :owner react--owner
                                         :svg react--svg)))
       (react--check-tag tag)
       (if svg (react--emit "create" id (symbol-name tag) "svg") (react--emit "create" id (symbol-name tag)))
       (puthash id mounted react--hosts)
       (react--set-ref mounted nil (plist-get props :ref))
       (let ((plist props))
         (while plist
           (when (and (cadr plist) (not (memq (car plist) '(:value :checked))))
             (react--set-prop id (car plist) (cadr plist)))
           (setq plist (cddr plist))))
       (when (and (plist-get props :inner-html) (react--element-children vnode))
         (error "A <%s> with :inner-html has children too; it can have one or the other" tag))
       (setf (react--host-children mounted)
             (mapcar (lambda (child)
                       (let ((mounted-child (react--mount child depth)))
                         (react--place id mounted-child nil)
                         mounted-child))
                     (react--element-children vnode)))
       ;; After the children: a <select>'s value names one of its options.
       (dolist (key '(:value :checked))
         (when (plist-get props key) (react--set-prop id key (plist-get props key))))
       mounted))
    (`(component . ,name)
     (let* ((spec (get name 'react-component))
            (props (react--component-props vnode))
            (initial (plist-get spec :initial-state))
            (instance (react--instance-create
                       :type name :spec spec :props props :depth depth :mounted t
                       :parent react--owner :svg react--svg)))
       ;; :initial-state may read a context: it needs the parent.
       (setf (react--instance-state instance) (and initial (funcall initial props)))
       (setf (react--instance-rendered-props instance) props
             (react--instance-rendered-state instance) (react--instance-state instance))
       (let ((react--owner instance))
         (setf (react--instance-child instance) (react--mount (react--render instance) (1+ depth))))
       (when (plist-get spec :did-mount) (push instance react--did-mount))
       instance))
    ('fragment
     ;; Its nodes are put in place by whoever puts the fragment there.
     (let ((props (react--element-props vnode)))
       (when (cl-set-difference (cl-loop for key in props by #'cddr collect key) '(:key))
         (error "A fragment takes no props but :key: %S" props))
       (let* ((children (mapcar (lambda (child) (react--mount child depth))
                                (react--element-children vnode)))
              (mounted (react--fragment-create :props props :children children
                                               :anchor (react--new-dom-id))))
         (react--emit "text" (react--fragment-anchor mounted) "")
         mounted)))))

(defun react--lifecycle (instance key &rest args)
  "Call INSTANCE's KEY (:did-mount ...): a function, or a list of them."
  (let ((value (plist-get (react--instance-spec instance) key)))
    (if (functionp value)
        (apply value instance args)
      (dolist (function value) (apply function instance args)))))

(cl-defstruct (react--ref-handle (:constructor react--ref-handle-create) (:copier nil))
  owner name)

(defun react-make-ref (self name)
  "A ref that SELF hands to a component below, to put on an element:
\(input (:ref (react-props self :input-ref))).  The element is then
SELF's ref NAME, for `react-focus', `react-invoke' and the others, as
if SELF had rendered it."
  (react--ref-handle-create :owner self :name name))

(defun react--ref-target (host ref)
  "The instance and the name under which HOST is kept for its :ref REF."
  (if (react--ref-handle-p ref)
      (cons (react--ref-handle-owner ref) (react--ref-handle-name ref))
    (cons (react--host-owner host) ref)))

(defun react--same-ref-p (a b)
  "Non-nil if the :ref values A and B name the same thing.
Not `equal': a ref made with `react-make-ref' holds an instance, whose
tree leads back to itself."
  (if (and (react--ref-handle-p a) (react--ref-handle-p b))
      (and (eq (react--ref-handle-owner a) (react--ref-handle-owner b))
           (equal (react--ref-handle-name a) (react--ref-handle-name b)))
    (and (not (react--ref-handle-p a)) (not (react--ref-handle-p b)) (equal a b))))

(defvar react--warned-tags nil "Capitalized tags already warned about.")

(defun react--check-tag (tag)
  "Warn, once, about a Capitalized TAG that is no component: HTML, SVG
and custom element names are lower case or have a hyphen, so it is
most likely a component whose name is misspelled or not loaded yet."
  (let ((name (symbol-name tag)))
    (when (and (<= ?A (aref name 0) ?Z) (not (string-search "-" name))
               (not (memq tag react--warned-tags)))
      (push tag react--warned-tags)
      (message "react: %s is not a defined component; it is rendered as an unknown element <%s> \
\(a misspelled name, or a file loaded too late?)" name (downcase name)))))

(defun react--set-ref (host old new)
  "HOST's :ref changed from OLD to NEW (nil: none): a name, or a ref made
with `react-make-ref'."
  (when old
    (pcase-let ((`(,owner . ,name) (react--ref-target host old)))
      (when (and owner (eq (cdr (assoc name (react--instance-refs owner))) host))
        (setf (react--instance-refs owner) (assoc-delete-all name (react--instance-refs owner))))))
  (when new
    (pcase-let ((`(,owner . ,name) (react--ref-target host new)))
      (when owner
        (setf (alist-get name (react--instance-refs owner) nil nil #'equal) host)))))

(defun react--component-props (vnode)
  "The props a component gets from its element VNODE."
  (let ((props (react--element-props vnode))
        (children (react--element-children vnode)))
    (if children (append props (list :children children)) props)))

(defun react--unmount (mounted)
  "Forget MOUNTED and everything below it.  The DOM node is the caller's."
  (cond ((react--host-p mounted)
         (remhash (react--host-dom-id mounted) react--hosts)
         (react--set-ref mounted (plist-get (react--host-props mounted) :ref) nil)
         (mapc #'react--unmount (react--host-children mounted)))
        ((react--fragment-p mounted)
         (mapc #'react--unmount (react--fragment-children mounted)))
        ((react--instance-p mounted)
         (react--lifecycle mounted :will-unmount)
         (dolist (effect (react--instance-effects mounted))
           (when (functionp (cddr effect)) (funcall (cddr effect))))
         (setf (react--instance-mounted mounted) nil)
         (react--unmount (react--instance-child mounted)))))

;;;; Reconciliation

(defun react--same-p (mounted vnode)
  "Non-nil if MOUNTED can be updated to show VNODE; otherwise it is replaced."
  (pcase (react--kind vnode)
    ('text (react--text-p mounted))
    (`(host . ,tag)
     (and (react--host-p mounted) (eq (react--host-tag mounted) tag)
          (equal (plist-get (react--host-props mounted) :key)
                 (plist-get (react--element-props vnode) :key))))
    (`(component . ,name)
     (and (react--instance-p mounted) (eq (react--instance-type mounted) name)
          (equal (plist-get (react--instance-props mounted) :key)
                 (plist-get (react--element-props vnode) :key))))
    ('fragment
     (and (react--fragment-p mounted)
          (equal (plist-get (react--fragment-props mounted) :key)
                 (plist-get (react--element-props vnode) :key))))))

(defun react--update (mounted vnode depth)
  "Make MOUNTED show VNODE with as few DOM operations as possible.
Returns what is mounted afterwards: MOUNTED itself, changed in place, or
a replacement that has taken its place in the DOM."
  (cond
   ((not (react--same-p mounted vnode))
    (let ((new (react--mount vnode depth)))
      (react--replace mounted new)
      (react--unmount mounted)
      new))
   ((react--fragment-p mounted)
    (setf (react--fragment-props mounted) (react--element-props vnode)
          (react--fragment-children mounted)
          (react--update-children nil (react--fragment-children mounted) (react--element-children vnode)
                                  depth (react--fragment-anchor mounted)))
    mounted)
   ((react--text-p mounted)
    (let ((text (react--text-of vnode)))
      (unless (equal text (react--text-text mounted))
        (setf (react--text-text mounted) text)
        (react--emit "set-text" (react--text-dom-id mounted) text)))
    mounted)
   ((react--host-p mounted)
    (let ((props (react--element-props vnode)))
      (react--update-props (react--host-dom-id mounted) (react--host-props mounted) props)
      (unless (react--same-ref-p (plist-get props :ref) (plist-get (react--host-props mounted) :ref))
        (react--set-ref mounted (plist-get (react--host-props mounted) :ref) (plist-get props :ref)))
      (setf (react--host-props mounted) props))
    (setf (react--host-children mounted)
          (let ((react--svg (react--host-svg mounted)))
            (react--update-children (react--host-dom-id mounted) (react--host-children mounted)
                                    (react--element-children vnode) depth)))
    mounted)
   (t
    (setf (react--instance-props mounted) (react--component-props vnode))
    (react--rerender mounted)
    mounted)))

(defun react--mounted-key (mounted)
  "The :key that MOUNTED was rendered with, or nil."
  (cond ((react--host-p mounted) (plist-get (react--host-props mounted) :key))
        ((react--instance-p mounted) (plist-get (react--instance-props mounted) :key))
        ((react--fragment-p mounted) (plist-get (react--fragment-props mounted) :key))))

(defun react--vnode-key (vnode)
  (and (consp vnode) (plist-get (react--element-props vnode) :key)))

(defun react--identities (items key-function)
  "How each of ITEMS is recognised among its siblings.
A child with a :key is (key . KEY); one without is (index . N), the N-th
child without a key.  A list without any keys is thus matched by position."
  (let ((unkeyed -1))
    (mapcar (lambda (item)
              (let ((key (funcall key-function item)))
                (if key (cons 'key key) (cons 'index (cl-incf unkeyed)))))
            items)))

(defun react--longest-increasing (numbers)
  "Positions in the vector NUMBERS of a longest increasing subsequence.
Returns a bool-vector: t at the positions that belong to it."
  (let* ((n (length numbers))
         (tails (make-vector n 0))      ; tails[k]: position where the best run of length k+1 ends
         (previous (make-vector n -1))
         (length 0)
         (keep (make-bool-vector n nil)))
    (dotimes (i n)
      (let ((low 0) (high length))
        (while (< low high)
          (let ((middle (/ (+ low high) 2)))
            (if (< (aref numbers (aref tails middle)) (aref numbers i))
                (setq low (1+ middle))
              (setq high middle))))
        (when (> low 0) (aset previous i (aref tails (1- low))))
        (aset tails low i)
        (when (= low length) (setq length (1+ length)))))
    (let ((i (if (> length 0) (aref tails (1- length)) -1)))
      (while (>= i 0)
        (aset keep i t)
        (setq i (aref previous i))))
    keep))

(defun react--update-children (parent-id mounted vnodes depth &optional end)
  "Update the children MOUNTED of the DOM node PARENT-ID to VNODES.
A new child takes over the old child with the same identity (see
`react--identities'): that one keeps its DOM node and, below it, the
state of its components, wherever it is in the new order.  Old children
that nobody took over are removed, the rest is created.  Returns the new
list of mounted children.

A fragment's children have no PARENT-ID: they are placed in front of
the node END (its anchor) and of each other."
  (let ((old (make-hash-table :test #'equal))
        (seen (make-hash-table :test #'equal))
        (index -1)
        placed)                         ; (MOUNTED . old position or nil), last child first
    (cl-mapc (lambda (identity child) (puthash identity (cons (cl-incf index) child) old))
             (react--identities mounted #'react--mounted-key) mounted)
    (cl-mapc
     (lambda (identity vnode)
       (let ((found (gethash identity old)))
         (cond (found
                (remhash identity old)
                (push (cons (react--update (cdr found) vnode depth) (car found)) placed))
               (t
                (when (gethash identity seen)
                  (message "react: two children have the key %S" (cdr identity)))
                (push (cons (react--mount vnode depth) nil) placed)))
         (puthash identity t seen)))
     (react--identities vnodes #'react--vnode-key) vnodes)
    ;; Nobody took these over.
    (let (gone)
      (maphash (lambda (_identity entry) (push entry gone)) old)
      (dolist (entry (sort gone (lambda (a b) (< (car a) (car b)))))
        (react--take-off (cdr entry))
        (react--unmount (cdr entry))))
    ;; The old children that are still in their old order relative to each
    ;; other (a longest such set) stay where they are.  Every other child,
    ;; new or out of order, is put in front of the child that follows it,
    ;; from the last child to the first.
    (let* ((kept (delq nil (mapcar #'cdr placed)))   ; old positions, last child first
           (stay (react--longest-increasing (vconcat (nreverse kept))))
           (position (length stay))
           (before end)
           out)
      (dolist (entry placed)
        (unless (and (cdr entry) (aref stay (cl-decf position)))
          (react--place parent-id (car entry) before))
        (setq before (react--dom-id (car entry)))
        (push (car entry) out))
      out)))

(defun react--rerender (instance)
  "Render INSTANCE again and reconcile what it rendered before."
  (setf (react--instance-dirty instance) nil)
  (let ((should-update (plist-get (react--instance-spec instance) :should-update)))
    ;; A skipped render leaves "what the last render saw" as it is: the next
    ;; question is again about the difference to what is on the page.
    (when (or (null should-update)
              (prog1 (react--instance-force instance) (setf (react--instance-force instance) nil))
              (funcall should-update instance (react--instance-rendered-props instance)
                       (react--instance-rendered-state instance)))
      (when (plist-get (react--instance-spec instance) :did-update)
        (push (list instance (react--instance-rendered-props instance) (react--instance-rendered-state instance))
              react--did-update))
      (setf (react--instance-rendered-props instance) (react--instance-props instance)
            (react--instance-rendered-state instance) (react--instance-state instance))
      (let ((react--owner instance)
            (react--svg (react--instance-svg instance)))
        (setf (react--instance-child instance)
              (react--update (react--instance-child instance) (react--render instance)
                             (1+ (react--instance-depth instance))))))))

;;;; Context

;; A value that a component hands to everything below it, however deep,
;; without passing it as a prop through every component in between: the
;; language, the signed-in user, a theme.

(react-define-component 'react-provider
  :render (lambda (self)
            (let ((children (react-props self :children)))
              (if (cdr children) (cons '<> children) (car children))))
  :did-update (lambda (self previous-props _previous-state)
                (unless (react--same-value-p (react-props self :value) (plist-get previous-props :value))
                  (setf (react--instance-readers self)
                        (cl-remove-if-not #'react--instance-mounted (react--instance-readers self)))
                  (mapc #'react--force-render (react--instance-readers self)))))

(defun react-provide (key value child)
  "An element that renders CHILD and hands VALUE to the components below
it under KEY (any Lisp data, compared with `equal').  They read it with
`react-context', and render again when VALUE changes, :pure or not.

  (react-provide \='language (react-state self :language)
    (jsx (Page)))"
  (list 'react-provider (list :context key :value value) child))

(defun react-context (self key &optional default)
  "The value that the nearest `react-provide' above SELF hands down under
KEY, or DEFAULT when there is none.  SELF renders again when it changes."
  (let ((ancestor (react--instance-parent self)))
    (while (and ancestor
                (not (and (eq (react--instance-type ancestor) 'react-provider)
                          (equal (react-props ancestor :context) key))))
      (setq ancestor (react--instance-parent ancestor)))
    (if (not ancestor)
        default
      (unless (memq self (react--instance-readers ancestor))
        (push self (react--instance-readers ancestor)))
      (react-props ancestor :value))))

(defun react-force-update (self)
  "Render SELF again at the end of this event, whatever :should-update says.
For a component that reads something other than its props and state."
  (react--force-render self)
  nil)

(defun react-refresh (&optional type)
  "Render every mounted component again (of the component TYPE only, a
symbol), whatever :should-update says: after global data changed."
  (react--each-instance
   (lambda (instance)
     (when (or (null type) (eq (react--instance-type instance) type))
       (react--force-render instance))))
  nil)

;;;; State

(defun react-plist-with (plist &rest changes)
  "A new plist: PLIST with the keys of CHANGES (a plist) set.
PLIST is not modified.  State and the records in it are changed this way:
  (react-plist-with todo :done t)"
  (let ((new (copy-sequence plist)))
    (while changes
      (setq new (plist-put new (car changes) (cadr changes)))
      (setq changes (cddr changes)))
    new))

(defun react-props (self &optional key)
  "The props of the component instance SELF, or the prop KEY."
  (if key (plist-get (react--instance-props self) key) (react--instance-props self)))

(defun react-state (self &optional key)
  "The state of the component instance SELF, or its value for KEY."
  (if key (plist-get (react--instance-state self) key) (react--instance-state self)))

(defun react-set-state (self &rest changes)
  "Change the state of SELF and schedule it to render again.
CHANGES is a plist that is merged into the state: (react-set-state self
:count 1).  Or it is one function, which gets the current state and
returns the plist to merge.  The old state plist is not modified.
Several changes during one event cause one render."
  (when (and (functionp (car changes)) (null (cdr changes)))
    (setq changes (funcall (car changes) (react--instance-state self))))
  (setf (react--instance-state self) (apply #'react-plist-with (react--instance-state self) changes))
  (when (react--instance-mounted self)
    (setf (react--instance-dirty self) t)
    (unless (memq self react--dirty) (push self react--dirty)))
  nil)

;;;; Skipping renders

(defun react--same-value-p (a b)
  "Non-nil if the prop or state values A and B are the same.
Strings and numbers are compared by value, everything else by identity:
a record or a list that was not replaced is the same, a new one is not
\(state is changed by building new values, never in place).  Two
closures of the same `lambda' (one in a render function makes a new one
every time) are the same when the values they captured are the same."
  (or (eq a b)
      (and (stringp a) (stringp b) (string= a b))
      (and (numberp a) (numberp b) (= a b))
      (and (react--ref-handle-p a) (react--ref-handle-p b) (react--same-ref-p a b))
      (and (functionp a) (functionp b) (react--same-closure-p a b))))

(defun react--same-atom-p (a b)
  (or (eq a b)
      (and (stringp a) (stringp b) (string= a b))
      (and (numberp a) (numberp b) (= a b))))

(defun react--same-closure-p (a b)
  "Non-nil if A and B are closures of the same code over the same values.
Captured values are compared one level deep (`eq', `string=', `='), so
that captured instances and trees are never walked."
  (cond
   ;; Byte-compiled: the code is shared, the captured values are the first
   ;; constants.
   ((and (byte-code-function-p a) (byte-code-function-p b))
    (and (= (length a) (length b))
         (equal (aref a 0) (aref b 0))
         (eq (aref a 1) (aref b 1))
         (let ((ca (aref a 2)) (cb (aref b 2)))
           (and (= (length ca) (length cb))
                (cl-every #'react--same-atom-p ca cb)))))
   ;; Interpreted, Emacs 30 and later: arguments, body, environment.
   ((and (fboundp 'interpreted-function-p)
         (funcall 'interpreted-function-p a) (funcall 'interpreted-function-p b))
    (and (eq (aref a 0) (aref b 0)) (eq (aref a 1) (aref b 1))
         (react--same-environment-p (aref a 2) (aref b 2))))
   ;; Interpreted, Emacs 29: (closure ENVIRONMENT ARGUMENTS . BODY).
   ((and (eq (car-safe a) 'closure) (eq (car-safe b) 'closure))
    (and (eq (cddr a) (cddr b))
         (react--same-environment-p (cadr a) (cadr b))))))

(defun react--same-environment-p (a b)
  "Non-nil if the lexical environments A and B bind the same values."
  (and (= (length a) (length b))
       (cl-every (lambda (x y)
                   (if (and (consp x) (consp y))
                       (and (eq (car x) (car y)) (react--same-atom-p (cdr x) (cdr y)))
                     (eq x y)))
                 a b)))

(defun react-shallow-equal (a b)
  "Non-nil if the plists A and B have the same keys with the same values.
Values are compared one level deep: see `react--same-value-p'."
  (and (= (length a) (length b))
       (let ((same t) (plist a))
         (while (and same plist)
           (setq same (and (plist-member b (car plist))
                           (react--same-value-p (cadr plist) (plist-get b (car plist)))))
           (setq plist (cddr plist)))
         same)))

(defun react-changed-p (new old &rest keys)
  "Non-nil if the plists NEW and OLD differ in one of KEYS.
For :should-update, to look only at the props that matter to the render:

  :should-update
  (lambda (self previous-props previous-state)
    (or (not (eq (react-state self) previous-state))
        (react-changed-p (react-props self) previous-props :todo)))

Leaving out a function prop is safe when the handlers that use it read
it when the event happens, (funcall (react-props self :on-change) ...),
because a skipped component still gets its new props."
  (cl-some (lambda (key) (not (react--same-value-p (plist-get new key) (plist-get old key)))) keys))

(defun react--pure-should-update (self previous-props previous-state)
  (not (and (react-shallow-equal (react--instance-props self) previous-props)
            (react-shallow-equal (react--instance-state self) previous-state))))

;;;; The host's entry points

(defun react-mount (element selector)
  "Render ELEMENT into the page element that the CSS SELECTOR names.
Rendering into the same place again updates what is there."
  (let ((root (gethash selector react--roots)))
    (if root
        (puthash selector (react--update root element 0) react--roots)
      (setq root (puthash selector (react--mount element 0) react--roots)))
    (apply #'react--emit "mount" selector (react--nodes (gethash selector react--roots))))
  selector)

(defun react-root (selector)
  "The component instance that `react-mount' rendered into SELECTOR, or
nil (nothing there, or an element rather than a component)."
  (let ((root (gethash selector react--roots)))
    (and (react--instance-p root) root)))

(defun react-unmount (selector)
  "Take down what `react-mount' rendered into SELECTOR."
  (let ((root (gethash selector react--roots)))
    (when root
      (react--take-off root)
      (react--unmount root)
      (remhash selector react--roots)))
  nil)

(defun react--render-dirty ()
  "Render every component whose state changed, parents first."
  (let ((rounds 0))
    (while (or react--dirty react--did-mount react--did-update react--effects)
      (when (> (cl-incf rounds) 100)
        (setq react--dirty nil react--did-mount nil react--did-update nil react--effects nil)
        (error "Components keep changing state while rendering"))
      ;; When one of them fails, what is left waits for the next flush
      ;; instead of being lost (instances that would never render again,
      ;; :did-mount functions never called), and the error goes on.
      (let ((dirty (sort react--dirty (lambda (a b) (< (react--instance-depth a) (react--instance-depth b))))))
        (setq react--dirty nil)
        (while dirty
          (let ((instance (pop dirty)))
            ;; A parent that rendered first may have updated or removed it.
            (when (and (react--instance-dirty instance) (react--instance-mounted instance))
              (condition-case err (react--rerender instance)
                (error (setq react--dirty (append dirty react--dirty))
                       (signal (car err) (cdr err))))))))
      (let ((mounted (nreverse react--did-mount)))
        (setq react--did-mount nil)
        (while mounted
          (let ((instance (pop mounted)))
            (when (react--instance-mounted instance)
              (condition-case err (react--lifecycle instance :did-mount)
                (error (setq react--did-mount (append react--did-mount (reverse mounted)))
                       (signal (car err) (cdr err))))))))
      (let ((updated (nreverse react--did-update)))
        (setq react--did-update nil)
        (while updated
          (let ((entry (pop updated)))
            (when (react--instance-mounted (car entry))
              (condition-case err (apply #'react--lifecycle (car entry) :did-update (cdr entry))
                (error (setq react--did-update (append react--did-update (reverse updated)))
                       (signal (car err) (cdr err))))))))
      (let ((effects (nreverse react--effects)))
        (setq react--effects nil)
        (while effects
          (let ((effect (pop effects)))
            (condition-case err (react--run-effect effect)
              (error (setq react--effects (append react--effects (reverse effects)))
                     (signal (car err) (cdr err))))))))))

(defun react-effect (self key deps function)
  "In a render of SELF: run FUNCTION after the render when DEPS changed.
KEY names the effect among SELF's (a symbol); DEPS is any Lisp data,
compared with `equal' to what it was the last time FUNCTION ran.
FUNCTION takes no arguments; if it returns a function, that one cleans
up: it is called before FUNCTION runs again, and when SELF is taken off.

A helper that keeps a timer running while a component is on the page:

  (defun my-use-interval (self ms function)
    (react-effect self \='interval ms
      (lambda ()
        (let ((timer (react-set-interval ms function)))
          (lambda () (react-clear-timer timer))))))"
  (let ((effect (assq key (react--instance-effects self))))
    (unless (and effect (equal (cadr effect) deps))
      (push (list self key deps function) react--effects)))
  nil)

(defun react--run-effect (effect)
  "Run EFFECT, (INSTANCE KEY DEPS FUNCTION), after cleaning up its last run."
  (pcase-let ((`(,instance ,key ,deps ,function) effect))
    (when (react--instance-mounted instance)
      (let ((old (assq key (react--instance-effects instance))))
        (when (and old (functionp (cddr old))) (funcall (cddr old)))
        (setf (alist-get key (react--instance-effects instance)) (cons deps (funcall function)))))))

(defun react-flush ()
  "Finish pending renders.  Returns the DOM operations since the last call.
The value is a vector of operations for the host, each a vector:

  [\"create\" ID TAG [\"svg\"]]  [\"text\" ID STRING]  [\"set-text\" ID STRING]
  [\"attr\" ID NAME VALUE]  [\"prop\" ID NAME VALUE]
  [\"listen\" ID EVENT OPTIONS]  [\"unlisten\" ID EVENT]
  [\"insert\" PARENT-ID ID BEFORE-ID]  [\"before\" ID BEFORE-ID]
  [\"replace\" OLD-ID ID]  [\"remove\" ID]
  [\"mount\" SELECTOR ID...]            the root's nodes (several: a fragment)
  [\"html\" ID HTML]                    cleaned HTML in the node (:inner-html)
  [\"invoke\" ID METHOD ARG...]         call a method of the DOM node
  [\"call\" REQUEST-ID COMMAND ARGUMENT]  do it and answer (`react-host-reply')
  [\"tell\" COMMAND ARGUMENT]             do it, no answer
  [\"cancel\" REQUEST-ID]"
  (react--render-dirty)
  (prog1 (vconcat (nreverse react--ops))
    (setq react--ops nil)))

(defun react-dispatch-event (dom-id name event)
  "The DOM node DOM-ID received the event NAME.  EVENT is a plist.
Runs the element's listener and returns the DOM operations that follow."
  (let* ((host (gethash dom-id react--hosts))
         (handler (and host (react--listener-function
                             (plist-get (react--host-props host) (intern (concat ":on-" name)))))))
    (when handler (funcall handler event)))
  (react-flush))

;;;; Events

(defun react-form-value (event name)
  "The value of the field NAME in the form that EVENT submitted, or nil.
A file field gives the file's name."
  (let ((field (cl-find-if (lambda (field) (equal (aref field 0) name)) (plist-get event :form))))
    (and field (aref field 1))))

(defun react-form-values (event name)
  "Every value of the field NAME (checkboxes, a multiple select)."
  (delq nil (mapcar (lambda (field) (and (equal (aref field 0) name) (aref field 1)))
                    (plist-get event :form))))

;;;; The page: DOM nodes

(defun react-ref (self name)
  "The element that SELF rendered with :ref NAME, or nil.
The value is only good for `react-invoke'."
  (cdr (assoc name (react--instance-refs self))))

(defun react-node-id (ref)
  "The number by which the page knows the DOM node of REF (`react-ref'),
for a command of the page: its `node(id)' returns the node."
  (and ref (react--host-dom-id ref)))

(defun react-invoke (self name method &rest args)
  "Call METHOD with ARGS on the DOM node of the element SELF rendered
with :ref NAME, after the DOM changes of this render.  METHOD is one of
\"focus\" \"blur\" \"select\" \"click\" \"scrollIntoView\" \"scrollTo\"
\"scrollBy\" \"setSelectionRange\" \"showModal\" \"show\" \"close\"
\"requestSubmit\" \"reset\" \"reportValidity\" \"setCustomValidity\"
\"play\" \"pause\" \"load\" \"requestFullscreen\" \"showPicker\".
ARGS are JSON data: (react-invoke self \"field\" \"setSelectionRange\" 0 3),
\(react-invoke self \"list\" \"scrollTo\" \='(:top 0 :behavior \"smooth\")).
Nothing happens when there is no such element."
  (let ((host (react-ref self name)))
    (when host (apply #'react--emit "invoke" (react--host-dom-id host) method args)))
  nil)

(defun react-set-property (self name property value)
  "Set the DOM PROPERTY of the element SELF rendered with :ref NAME to
VALUE, after the DOM changes of this render.  PROPERTY is one of
\"indeterminate\" \"selectedIndex\" \"open\" \"muted\" \"volume\"
\"currentTime\" \"playbackRate\" \"loop\" \"scrollTop\" \"scrollLeft\"
\(:value and :checked are props).  Booleans are t and nil."
  (let ((host (react-ref self name)))
    (when host
      (react--emit "prop" (react--host-dom-id host) property
                   (if (memq value '(nil t)) (if value t :false) value))))
  nil)

(defun react-measure (self name function)
  "Measure the element SELF rendered with :ref NAME, after the DOM changes
of this render, and call FUNCTION with a plist: (:x :y :width :height)
of its box, (:scrollTop :scrollLeft :scrollWidth :scrollHeight
:clientWidth :clientHeight), and for audio and video (:currentTime
:duration :paused).  Nothing happens when there is no such element."
  (let ((host (react-ref self name)))
    (when host
      (react-host-call "measure" (list :node (react--host-dom-id host))
                       (lambda (ok value) (when ok (funcall function value)))))))

(defun react-focus (self name)
  "Give the keyboard focus to the element SELF rendered with :ref NAME."
  (react-invoke self name "focus"))

;;;; The page: things that take time

(defun react-host-call (command argument &optional function keep)
  "Ask the host to do COMMAND with ARGUMENT (JSON data).
When the host answers, FUNCTION is called with OK (non-nil for success)
and the VALUE of the answer.  With KEEP, FUNCTION stays for further
answers (an interval).  Returns the request, for `react-cancel'.
This is what `react-set-timeout' and `react-fetch' are made of."
  (let ((id (cl-incf react--next-request)))
    (when function (puthash id (cons function keep) react--requests))
    (react--emit "call" id command argument)
    id))

(defun react-host-tell (command argument)
  "Tell the host to do COMMAND with ARGUMENT (JSON data); no answer.
COMMAND is one of the host's notices or one the page registered in
`globalThis.elispReactCommands' (see the README)."
  (react--emit "tell" command argument)
  nil)

(defun react-page-call (name args)
  "The page's script calls the Lisp function NAME (a string) with ARGS (a
vector of JSON data): `window.elispReact.send(NAME, ...ARGS)'.  Returns
the DOM operations that follow."
  (apply (intern name) (append args nil))
  (react-flush))

(defun react-cancel (request)
  "Forget REQUEST (a timer, a fetch): its function will not be called."
  (when request
    (remhash request react--requests)
    (react--emit "cancel" request))
  nil)

(defun react-host-reply (request ok value)
  "The host's answer to REQUEST.  Returns the DOM operations that follow."
  (let ((entry (gethash request react--requests)))
    (when entry
      (unless (cdr entry) (remhash request react--requests))
      (funcall (car entry) ok value)))
  (react-flush))

(defun react-host-replies (replies)
  "Several answers of the host, REPLIES, a vector of [REQUEST OK VALUE]:
what arrived while Lisp was busy.  Runs each waiting function, then
renders once.  Returns the DOM operations that follow."
  (let (failure)
    (mapc (lambda (reply)
            (let ((entry (gethash (aref reply 0) react--requests)))
              (when entry
                (unless (cdr entry) (remhash (aref reply 0) react--requests))
                (condition-case err (funcall (car entry) (aref reply 1) (aref reply 2))
                  (error (unless failure (setq failure err)))))))
          replies)
    ;; One failure does not cost the others their answer; it is reported,
    ;; and what they changed renders at the next flush.
    (when failure (signal (car failure) (cdr failure))))
  (react-flush))

(defun react-set-timeout (milliseconds function)
  "Call FUNCTION, without arguments, once after MILLISECONDS.
Returns the timer, for `react-clear-timer'."
  (react-host-call "timeout" milliseconds (lambda (_ok _value) (funcall function))))

(defun react-set-interval (milliseconds function)
  "Call FUNCTION, without arguments, every MILLISECONDS.
Returns the timer; stop it with `react-clear-timer' (in :will-unmount)."
  (react-host-call "interval" milliseconds (lambda (_ok _value) (funcall function)) t))

(defalias 'react-clear-timer #'react-cancel)

(defconst react--fetch-options
  '(:credentials :cache :redirect :mode :keepalive :priority :referrerPolicy :as)
  "Options of `react-fetch' that go to the browser's fetch as they are.")

(defun react--form-fields (form)
  "FORM, a list NAME VALUE ..., as the host wants it: [[NAME VALUE]...].
A VALUE that is a ref (`react-ref') sends the files chosen in that input."
  (let (fields)
    (while form
      (let ((value (cadr form)))
        (push (vector (car form)
                      (if (react--host-p value) (list :file (react--host-dom-id value)) (or value "")))
              fields))
      (setq form (cddr form)))
    (vconcat (nreverse fields))))

(defun react-fetch (url &rest options)
  "Request URL with the browser's fetch.  OPTIONS is a plist:

:method STRING   \"GET\" by default
:headers PLIST   (:content-type \"application/json\")
:body STRING
:file REF        instead of :body: send the file the visitor chose in a
                 file input, (react-ref SELF NAME); its content is the
                 body, whatever its size
:form LIST       instead of :body: NAME VALUE ..., sent as
                 multipart/form-data; a VALUE is a string, or a ref to a
                 file input whose files are sent
:as \='base64      the body as base64 text (:base64 in the response)
                 instead of :text, for bytes; see `react-response-bytes'
:credentials :cache :redirect :mode :keepalive :priority :referrerPolicy
                 as in fetch: :credentials \"include\" sends cookies to
                 another origin, :cache \"no-store\", ...
:then FUNCTION   (RESPONSE), a plist (:status 200 :ok t :url \"...\"
                 :redirected nil :headers (:content-type \"...\" ...)
                 :text \"...\"); an HTTP error status is a response
                 too, with :ok nil.  Header names are lower case.
:catch FUNCTION  (MESSAGE), when there was no response at all

Returns the request, for `react-cancel'.  `react-response-json' reads a
JSON body."
  (let ((then (plist-get options :then))
        (catch (plist-get options :catch))
        (file (plist-get options :file))
        (form (plist-get options :form)))
    (react-host-call
     "fetch"
     (append (list :url url :method (or (plist-get options :method) "GET")
                   :headers (plist-get options :headers) :body (plist-get options :body))
             (and file (list :file (react--host-dom-id file)))
             (and form (list :form (react--form-fields form)))
             (cl-loop for key in react--fetch-options
                      for value = (plist-get options key)
                      when value
                      append (list key (if (and (symbolp value) (not (eq value t))) (symbol-name value) value))))
     (lambda (ok value)
       (cond ((and ok then) (funcall then value))
             (ok nil)
             (catch (funcall catch value))
             (t (message "react-fetch: %s: %s" url value)))))))

(defun react--connection (command argument handlers message)
  "Ask the host for a connection: COMMAND with ARGUMENT, answered again
and again.  HANDLERS is a plist :on-open :on-message :on-close :on-error;
an answer's :type names the one to call.  MESSAGE turns a \"message\"
answer into the argument of :on-message.  Returns the connection."
  (let (connection)
    (setq connection
          (react-host-call
           command argument
           (lambda (_ok value)
             (let* ((type (or (plist-get value :type) "message"))
                    (handler (plist-get handlers (if (member type '("open" "close" "error"))
                                                     (intern (concat ":on-" type))
                                                   :on-message))))
               ;; After "close" nothing more comes.
               (when (equal type "close") (remhash connection react--requests))
               (when handler
                 (pcase type
                   ("close" (funcall handler (plist-get value :code) (plist-get value :reason)))
                   ((or "open" "error") (funcall handler))
                   (_ (funcall handler (funcall message value)))))))
           t))
    connection))

(defun react-websocket (url &rest options)
  "Open a WebSocket to URL (ws:, wss:, or a path of this site).
OPTIONS is a plist:

:on-open FUNCTION      ()
:on-message FUNCTION   (TEXT): each text message
:on-close FUNCTION     (CODE REASON)
:on-error FUNCTION     ()
:protocols LIST        sub-protocols (strings)

Returns the connection: `react-websocket-send' sends on it, `react-cancel'
closes it (in :will-unmount)."
  (react--connection "websocket" (list :url url :protocols (vconcat (plist-get options :protocols)))
                     options (lambda (value) (plist-get value :data))))

(defun react-websocket-send (connection text)
  "Send TEXT on CONNECTION, a WebSocket from `react-websocket'.
The text goes once the DOM changes of this event are applied.  On a
connection that is not open (not yet, or not any more) it is not sent:
the page only logs a warning in its console (\"websocket-send ... the
connection is not open\"), and Lisp is not told.  Send after :on-open."
  (react--emit "tell" "websocket-send" (list :request connection :data text))
  nil)

(defun react-event-source (url &rest options)
  "Listen to the server-sent events of URL (an EventSource).
OPTIONS is a plist:

:on-message FUNCTION   (EVENT), a plist (:type \"message\" :data \"...\" :id ...)
:events LIST           further event names (strings) to receive; their
                       EVENT has :type set to the name
:on-open FUNCTION      ()
:on-error FUNCTION     (): the connection broke; the browser reconnects
:on-close FUNCTION     (nil nil): the browser gave up
:with-credentials t    send cookies to another origin

Returns the connection; `react-cancel' closes it (in :will-unmount)."
  (react--connection "event-source"
                     (list :url url :events (vconcat (plist-get options :events))
                           :withCredentials (and (plist-get options :with-credentials) t))
                     options #'identity))

(defun react-response-json (response)
  "The body of RESPONSE as Lisp data: objects are plists, arrays vectors."
  (json-parse-string (plist-get response :text) :object-type 'plist :null-object nil :false-object nil))

(defun react-response-bytes (response)
  "The body of RESPONSE, fetched with :as \='base64, as a unibyte string."
  (base64-decode-string (plist-get response :base64)))

(defun react-response-header (response name)
  "The header NAME (a string, any case) of RESPONSE, or nil."
  (plist-get (plist-get response :headers) (intern (concat ":" (downcase name)))))

;;;; async / await

;; An "awaitable" is a function of two arguments, RESOLVE and REJECT: it
;; starts something and calls one of them, once, when that has finished.

(define-error 'react-async-error "Asynchronous operation failed")

(defun react-sleep (milliseconds)
  "An awaitable that finishes after MILLISECONDS."
  (lambda (resolve _reject)
    (react-set-timeout milliseconds (lambda () (funcall resolve nil)))))

(defun react-fetch-async (url &rest options)
  "An awaitable for `react-fetch': its value is the response.
OPTIONS are those of `react-fetch' but :then and :catch.  Without a
response the await signals `react-async-error'; an HTTP error status is
a response."
  (lambda (resolve reject)
    (apply #'react-fetch url :then resolve :catch reject options)))

;; `react-async' returns a task, which is an awaitable too: another body
;; can wait for its value.

(cl-defstruct (react-task (:constructor react--task-create) (:copier nil))
  iterator
  request      ; what the awaitable it waits for returned (a request), for cancelling
  state        ; nil while running, then `done', `failed' or `cancelled'
  value        ; the body's value, or the failure's message
  waiting)     ; (RESOLVE . REJECT) of those who await it

(defun react--await-value (answer)
  "What `react-await' evaluates to, given the runner's ANSWER."
  (if (eq (car-safe answer) 'react--rejected)
      (signal 'react-async-error (list (cdr answer)))
    (cdr answer)))

(defun react--awaitable (value)
  "VALUE as a function of RESOLVE and REJECT: a task becomes one."
  (if (react-task-p value)
      (lambda (resolve reject)
        (pcase (react-task-state value)
          ('done (funcall resolve (react-task-value value)))
          ((or 'failed 'cancelled) (funcall reject (react-task-value value)))
          (_ (push (cons resolve reject) (react-task-waiting value)))))
    value))

(defmacro react-await (awaitable)
  "Inside `react-async': wait for AWAITABLE and return its value.
AWAITABLE is a function of RESOLVE and REJECT, or a task (the value of
another `react-async').  The Lisp code stops here and Emacs goes back to
the page; when the page has the answer, the code goes on.  If the
operation fails, this signals `react-async-error', which `condition-case'
around it can handle.  State may have changed in the meantime: read it
again after an await."
  `(react--await-value (iter-yield ,awaitable)))

(defun react--task-settle (task state value)
  (setf (react-task-state task) state (react-task-value task) value (react-task-request task) nil)
  (let ((waiting (reverse (react-task-waiting task))))
    (setf (react-task-waiting task) nil)
    (dolist (waiter waiting)
      (funcall (if (eq state 'done) (car waiter) (cdr waiter)) value))))

(defun react--async-step (task answer)
  "Run TASK until its next await, handing it ANSWER for the last one.
An awaitable that answers at once (a task that has finished, say) does
not make the stack deeper: the loop goes on instead."
  (let ((next (list answer)))
    (while next
      (let ((answer (car next)) awaitable)
        (setq next nil)
        (unless (react-task-state task)
          (condition-case err
              (setq awaitable (react--awaitable (iter-next (react-task-iterator task) answer)))
            (iter-end-of-sequence (react--task-settle task 'done (cdr err)))
            (error
             (let ((waiting (react-task-waiting task)))
               (react--task-settle task 'failed (error-message-string err))
               ;; Nobody waits for this task: the error is the page's.
               (unless waiting (signal (car err) (cdr err))))))
          (when awaitable
            (let ((calling t) settled)
              (setf (react-task-request task)
                    (funcall awaitable
                             (lambda (value)
                               (if calling (setq settled (cons 'react--resolved value))
                                 (react--async-step task (cons 'react--resolved value))))
                             (lambda (message)
                               (if calling (setq settled (cons 'react--rejected message))
                                 (react--async-step task (cons 'react--rejected message))))))
              (setq calling nil)
              (when settled (setq next (list settled))))))))))

(defconst react--await-forbidden
  '(lambda function closure with-temp-buffer with-current-buffer save-excursion save-current-buffer
    save-restriction save-match-data mapcar mapc mapcan mapconcat seq-doseq seq-do seq-map maphash
    cl-loop unwind-protect)
  "Forms that `react-await' cannot be inside, because generator.el's
rewrite of `react-async' does not reach into them.")

(defun react--check-awaits (form &optional inside)
  "Signal an error if a `react-await' in FORM is inside a form it cannot be in."
  (when (consp form)
    (cond ((eq (car form) 'quote))
          ((memq (car form) '(react-await iter-yield))
           (when inside
             (error "react-await cannot be inside %s (generator.el does not rewrite it): %S"
                    inside form))
           (react--check-awaits (cdr form) inside))
          (t (let ((head (and (symbolp (car form)) (memq (car form) react--await-forbidden) (car form))))
               (while (consp form)
                 (react--check-awaits (car form) (or inside head))
                 (setq form (cdr form))))))))

(defmacro react-async (&rest body)
  "Run BODY, in which `react-await' waits for the page.  Returns a task.

  (react-async
    (react-set-state self :status \='loading)
    (condition-case nil
        (let ((response (react-await (react-fetch-async \"/data.json\"))))
          (react-set-state self :status \='loaded
                           :data (react-response-json response)))
      (react-async-error (react-set-state self :status \='failed))))

BODY starts at once and runs until its first await; the rest happens when
the page answers.  The task is the body's value to whoever awaits it
\(another body, `react-all'); `react-task-cancel' stops it.

BODY is a generator (see `iter-lambda'), with these rules:
- `react-await' may be in loops and conditionals, not inside a `lambda',
  `with-temp-buffer', `save-excursion', `mapcar' and the like, or
  `unwind-protect' (its body as well as its cleanup): an error at macro
  expansion says so.
- A closure made in a loop that awaits shares the loop variable with the
  others: bind it again inside, (let ((item item)) (lambda () item))."
  (declare (indent 0))
  (react--check-awaits body)
  `(let ((task (react--task-create :iterator (funcall (iter-lambda () ,@body)))))
     (react--async-step task nil)
     task))

(defun react-task-cancel (task)
  "Stop TASK: the request it waits for is cancelled, it never goes on,
and those who await it get a `react-async-error' (\"cancelled\")."
  (when (and (react-task-p task) (null (react-task-state task)))
    (let ((request (react-task-request task)))
      (when (integerp request) (react-cancel request)))
    (react--task-settle task 'cancelled "cancelled"))
  nil)

(defun react-all (awaitables)
  "An awaitable whose value is the list of the values of AWAITABLES
\(functions of RESOLVE and REJECT, or tasks), in order, once all have
answered; it fails as soon as one of them fails."
  (lambda (resolve reject)
    (let* ((awaitables (mapcar #'react--awaitable awaitables))
           (values (make-vector (length awaitables) nil))
           (left (length awaitables))
           (failed nil) (index -1))
      (if (zerop left)
          (funcall resolve nil)
        (dolist (awaitable awaitables)
          (let ((at (cl-incf index)))
            (funcall awaitable
                     (lambda (value)
                       (unless failed
                         (aset values at value)
                         (when (zerop (cl-decf left)) (funcall resolve (append values nil)))))
                     (lambda (message)
                       (unless failed (setq failed t) (funcall reject message))))))))
    nil))

(defun react-race (awaitables)
  "An awaitable that answers as the first of AWAITABLES answers."
  (lambda (resolve reject)
    (let ((settled nil))
      (dolist (awaitable (mapcar #'react--awaitable awaitables))
        (funcall awaitable
                 (lambda (value) (unless settled (setq settled t) (funcall resolve value)))
                 (lambda (message) (unless settled (setq settled t) (funcall reject message))))))
    nil))

;;;; The page: its own events

(defun react-listen-page (target event function &rest options)
  "Call FUNCTION at each EVENT of the window or the document.
TARGET is `window' or `document'; EVENT a name, \"keydown\", \"resize\",
\"scroll\", \"visibilitychange\" ...  FUNCTION gets a plist (:type :key
:width :height :x :y :visibility): the event, the page's size, its scroll
position and whether it is visible.  OPTIONS:

:keys LIST     only these keys (\"/\" \"Escape\" \"ArrowLeft\"), for key events
:prevent t     the browser does not act on them (preventDefault)
:throttle MS   at most one call per MS milliseconds; the last event of a
               burst is not lost

Returns the listener; `react-cancel' removes it (in :will-unmount)."
  (react-host-call "page-listen"
                   (list :target (format "%s" target) :event event
                         :keys (vconcat (plist-get options :keys))
                         :prevent (and (plist-get options :prevent) t)
                         :throttle (plist-get options :throttle))
                   (lambda (_ok value) (funcall function value))
                   t))

(defun react-media-query (query function)
  "Call FUNCTION with t or nil: whether the CSS media QUERY matches, as
soon as the page has answered and at each change.  QUERY is, for
example, \"(prefers-color-scheme: dark)\" or \"(max-width: 600px)\".
Returns the listener, for `react-cancel'."
  (react-host-call "media" (list :query query)
                   (lambda (_ok value) (funcall function (plist-get value :matches)))
                   t))

(defun react-observe-visible (self name function &rest options)
  "Call FUNCTION with VISIBLE and RATIO whenever the element SELF rendered
with :ref NAME comes into view or leaves it (an IntersectionObserver).
OPTIONS: :margin \"200px\" counts the element as visible that much
before it is; :threshold 0.5, half of it.  Use it after the element is on
the page (:did-mount).  Returns the observer, for `react-cancel'."
  (let ((host (react-ref self name)))
    (when host
      (react-host-call "observe-visible"
                       (list :node (react--host-dom-id host) :margin (plist-get options :margin)
                             :threshold (plist-get options :threshold))
                       (lambda (ok value)
                         (when ok (funcall function (plist-get value :visible) (plist-get value :ratio))))
                       t))))

;;;; The page: its language and time

;; The page's Emacs runs in the C locale: `format-time-string' writes
;; English names, `string-collate-lessp' compares code points, and the
;; zone of `format-time-string' is the browser's whatever it is told
;; (except t, UTC).  The browser knows better; Lisp asks it.

(defvar react--locale nil "(:languages [...] :timeZone ... :offset MINUTES) of the browser.")

(defun react--locale-set (locale)
  (setq react--locale locale)
  nil)

(defun react-locale (&optional part)
  "The visitor's languages and time zone: (:languages [\"ja\" \"en-US\"]
:timeZone \"Asia/Tokyo\" :offset 540), or its PART.  :offset is the
minutes east of UTC now.  Known from the start on."
  (if part (plist-get react--locale part) react--locale))

(defun react--intl-items (items)
  (vconcat (mapcar (lambda (item)
                     (let ((value (plist-get item :value)))
                       (list :type (format "%s" (plist-get item :type))
                             :value (if (and (listp value) value) (vconcat value) value)
                             :unit (plist-get item :unit)
                             :options (plist-get item :options))))
                   items)))

(defun react-intl (items function &optional locale)
  "Have the browser's Intl write ITEMS, then call FUNCTION with the texts,
a list in the same order.  An item is a plist:

  (:type number :value 1234567 :options (:notation \"compact\"))  \"123万\"
  (:type date :value MILLISECONDS-OR-ISO :options (:dateStyle \"medium\"))
  (:type relative :value -3 :unit \"day\")                        \"3 日前\"
  (:type plural :value 2)                                          \"other\"
  (:type list :value (\"a\" \"b\"))                               \"a、b\"
  (:type sort :value (\"b\" \"a\"))       a list, sorted for the locale

Options are those of Intl's constructors.  LOCALE defaults to the
visitor's languages.  The texts arrive later: keep them in state.
Returns the request, for `react-cancel'."
  (react-host-call "intl" (list :items (react--intl-items items) :locale locale)
                   (lambda (ok value)
                     (when ok
                       (funcall function (mapcar (lambda (text) (if (vectorp text) (append text nil) text))
                                                 (append value nil)))))))

(defun react-intl-async (items &optional locale)
  "An awaitable for `react-intl': its value is the list of texts."
  (lambda (resolve _reject) (react-intl items resolve locale)))

;;;; The page: its address

(defvar react--location nil "The page's address: (:href :pathname :search :hash).")
(defvar react--location-watchers nil "Functions called with a new address.")

(defun react--location-set (location)
  (setq react--location location)
  nil)

(defun react--location-changed (location)
  "The page has a new address, LOCATION.  Returns the DOM operations that follow."
  (setq react--location location)
  (dolist (function react--location-watchers) (funcall function location))
  (react-flush))

(defun react-location (&optional part)
  "The page's address: a plist (:href :pathname :search :hash), or its PART.
Known from the start on, so a render can read it.  In elisp-studio's
preview the address is one the host keeps (it starts at \"/\")."
  (if part (plist-get react--location part) react--location))

(defun react-location-watch (function)
  "Call FUNCTION with the new address (see `react-location') whenever it
changes: a link, Back or Forward, `react-navigate'.  Returns a handle for
`react-location-unwatch'."
  (push function react--location-watchers)
  function)

(defun react-location-unwatch (handle)
  "Stop the watcher HANDLE of `react-location-watch'."
  (setq react--location-watchers (delq handle react--location-watchers))
  nil)

(defun react-navigate (url &optional replace)
  "Go to URL: a new entry in the history (with REPLACE, the current one is
replaced).  Within the page's origin the page stays and the watchers of
`react-location-watch' run; another origin is loaded."
  (react--emit "tell" "navigate" (list :url url :replace (and replace t)))
  nil)

(defun react-history-go (delta)
  "Move DELTA entries in the history: -1 is Back."
  (react--emit "tell" "history-go" (list :delta delta))
  nil)

(defun react-set-title (text)
  "Make TEXT the document's title."
  (react--emit "tell" "title" (list :text text))
  nil)

(defun react-set-meta (name content)
  "Set the <meta> NAME (\"description\", \"og:title\", ...) to CONTENT;
nil removes it."
  (react--emit "tell" "meta" (list :name name :content content))
  nil)

(defun react-url-query (search)
  "The query string SEARCH (\"?q=%E6%8B%AC&page=2\", with or without
\"?\") as an alist ((\"q\" . \"括\") (\"page\" . \"2\")).
Escapes are read as UTF-8; \"+\" is a space."
  (let ((search (if (string-prefix-p "?" (or search "")) (substring search 1) (or search ""))))
    (delq nil
          (mapcar (lambda (pair)
                    (unless (string-empty-p pair)
                      (let ((at (string-search "=" pair)))
                        (cons (react--unescape (if at (substring pair 0 at) pair))
                              (react--unescape (if at (substring pair (1+ at)) ""))))))
                  (split-string search "&")))))

(defun react--unescape (text)
  "TEXT of a URL with its %XX escapes and \"+\" undone, read as UTF-8."
  (let ((bytes (encode-coding-string (string-replace "+" " " text) 'utf-8))
        (out nil) (i 0))
    (while (< i (length bytes))
      (let ((byte (aref bytes i)))
        (if (and (= byte ?%) (<= (+ i 3) (length bytes))
                 (string-match-p "\\`[0-9A-Fa-f][0-9A-Fa-f]\\'" (substring bytes (1+ i) (+ i 3))))
            (progn (push (string-to-number (substring bytes (1+ i) (+ i 3)) 16) out)
                   (setq i (+ i 3)))
          (push byte out)
          (setq i (1+ i)))))
    (react--valid-text (decode-coding-string (apply #'unibyte-string (nreverse out)) 'utf-8))))

;;;; Queries

;; Data that components fetch, kept by key and shared: two components that
;; ask for the same key share one request and one result, a component that
;; comes back (the Back button) shows what was loaded before at once, and a
;; key is loaded again when it is stale or invalidated.

(cl-defstruct (react--query (:constructor react--query-create))
  status data error         ; loading, success or error; the last data; the error
  fetched                   ; `float-time' of the last success, or nil: stale
  loading                   ; the generation being loaded, or nil
  (generation 0)            ; answers of older generations are dropped
  loader stale-ms
  subscribers)              ; instances that read it

(defvar react--queries (make-hash-table :test #'equal) "Key -> `react--query'.")

(defun react-query (self key loader &rest options)
  "The data under KEY for the component SELF, loaded by LOADER.
KEY is any Lisp data compared with `equal', a list such as
\=(\"videos\" \"home\") say.  LOADER is a function of no arguments that
returns an awaitable (`react-fetch-async', or any function of RESOLVE and
REJECT); its value is the data.

Returns a plist (:status STATUS :data DATA :error ERROR :fetching BOOL):
STATUS is `loading' (nothing yet), `success' or `error'.  The data of the
last success stays while the key is loaded again (:fetching t).

SELF renders again when the key's data or status changes, :pure or not.
Requests are shared: other components asking for KEY while it loads
wait for the same answer.  When SELF asks for the first time, a key whose
data is older than :stale-ms (OPTIONS, default 0) is loaded again in
the background.  See `react-invalidate' and `react-query-set'."
  (let ((query (or (gethash key react--queries)
                   (puthash key (react--query-create :status 'loading) react--queries))))
    (setf (react--query-loader query) loader
          (react--query-stale-ms query) (or (plist-get options :stale-ms) 0))
    (unless (memq self (react--query-subscribers query))
      (push self (react--query-subscribers query))
      (when (react--query-stale-p query) (react--query-load key query)))
    (list :status (react--query-status query) :data (react--query-data query)
          :error (react--query-error query) :fetching (and (react--query-loading query) t))))

(defun react--query-stale-p (query)
  (let ((fetched (react--query-fetched query)))
    (or (null fetched)
        (> (* 1000 (- (float-time) fetched)) (react--query-stale-ms query)))))

(defun react--query-load (key query)
  "Load QUERY (under KEY) unless it is loading already."
  (unless (eql (react--query-loading query) (react--query-generation query))
    (let ((generation (react--query-generation query)))
      (setf (react--query-loading query) generation)
      (funcall (funcall (react--query-loader query))
               (lambda (data) (react--query-settle key generation 'success data nil))
               (lambda (error) (react--query-settle key generation 'error nil error))))))

(defun react--query-settle (key generation status data error)
  (let ((query (gethash key react--queries)))
    (when (and query (= generation (react--query-generation query)))
      (setf (react--query-loading query) nil
            (react--query-status query) (if (and (eq status 'error) (react--query-fetched query)) 'success status)
            (react--query-error query) error)
      (when (eq status 'success)
        (setf (react--query-data query) data
              (react--query-fetched query) (float-time)))
      (react--query-notify query))))

(defun react--query-notify (query)
  "Render the components that read QUERY again; forget those that are gone."
  (setf (react--query-subscribers query)
        (cl-remove-if-not #'react--instance-mounted (react--query-subscribers query)))
  (mapc #'react--force-render (react--query-subscribers query)))

(defun react--query-key-match-p (prefix key)
  (or (equal prefix key)
      (and (consp prefix) (consp key) (<= (length prefix) (length key))
           (equal prefix (cl-subseq key 0 (length prefix))))))

(defun react-invalidate (prefix)
  "Make the data of every key that is PREFIX, or a list that starts with
the list PREFIX, stale: answers on their way are dropped, and keys that
mounted components read are loaded again."
  (maphash (lambda (key query)
             (when (react--query-key-match-p prefix key)
               (cl-incf (react--query-generation query))
               (setf (react--query-fetched query) nil
                     (react--query-loading query) nil
                     (react--query-subscribers query)
                     (cl-remove-if-not #'react--instance-mounted (react--query-subscribers query)))
               (when (react--query-subscribers query)
                 (react--query-load key query)
                 (react--query-notify query))))
           react--queries)
  nil)

(defun react-query-set (key data)
  "Put DATA under KEY as if it had been loaded (an optimistic update, or
the answer of a request that changed it).  Components that read it
render again."
  (let ((query (or (gethash key react--queries)
                   (puthash key (react--query-create) react--queries))))
    (cl-incf (react--query-generation query))
    (setf (react--query-status query) 'success (react--query-data query) data
          (react--query-error query) nil (react--query-loading query) nil
          (react--query-fetched query) (float-time))
    (react--query-notify query))
  data)

(defun react-query-data (key)
  "The data under KEY, or nil, without reading it for a component."
  (let ((query (gethash key react--queries)))
    (and query (react--query-data query))))

;;;; The page: localStorage

;; The host hands over this page's stored values when it starts, so reading
;; is immediate.  Values are any printable Lisp data.

(defun react--storage-load (entries)
  "ENTRIES is a vector of [KEY TEXT]: what the page has stored.
Values whose time is up (`react-storage-set' with MAX-AGE) are removed."
  (clrhash react--storage)
  (mapc (lambda (entry) (puthash (aref entry 0) (aref entry 1) react--storage)) entries)
  (maphash (lambda (key _text)
             (when (eq (react--storage-read key) 'react--expired)
               (react-storage-remove key)))
           (copy-hash-table react--storage))
  nil)

(defun react--storage-read (key)
  "The value under KEY, `react--expired' when its time is up, or
`react--absent'."
  (let ((text (gethash key react--storage)))
    (if (not text)
        'react--absent
      (let ((value (condition-case nil (car (read-from-string text)) (error 'react--absent))))
        (if (eq (car-safe value) 'react--expiring)
            (if (< (nth 1 value) (float-time)) 'react--expired (nth 2 value))
          value)))))

(defvar react--storage-watchers (make-hash-table :test #'equal)
  "Key -> functions to call when another tab changes the stored value.")

(defun react--storage-changed (key text)
  "Another tab stored TEXT under KEY (nil: removed it).
Returns the DOM operations that follow."
  (if text (puthash key text react--storage) (remhash key react--storage))
  (dolist (function (gethash key react--storage-watchers))
    (funcall function (react-storage-get key)))
  (react-flush))

(defun react-storage-watch (key function)
  "Call FUNCTION with the new value when another tab changes KEY.
The value is nil when the other tab removed it.  Use it to merge what
the other tab stored, or to render again.  Returns a handle for
`react-storage-unwatch' (in :will-unmount)."
  (push function (gethash key react--storage-watchers))
  (cons key function))

(defun react-storage-unwatch (handle)
  "Stop the watcher HANDLE that `react-storage-watch' returned."
  (puthash (car handle) (delq (cdr handle) (gethash (car handle) react--storage-watchers))
           react--storage-watchers)
  nil)

(defun react-storage-get (key &optional default)
  "The Lisp value stored under KEY in the page's localStorage, or DEFAULT
\(also when it was stored with a MAX-AGE that has passed)."
  (let ((value (react--storage-read key)))
    (if (memq value '(react--absent react--expired)) default value)))

(defun react-storage-set (key value &optional max-age)
  "Store the Lisp VALUE under KEY in the page's localStorage.
VALUE replaces what is there, also what another tab of the page stored
since this one read it: watch the key (`react-storage-watch') and merge
before writing when tabs share a list.  With MAX-AGE (seconds) the value
is forgotten that long after: a later start removes it, and
`react-storage-get' no longer returns it."
  (let ((text (let ((print-length nil) (print-level nil))
                (prin1-to-string (if max-age (list 'react--expiring (+ (float-time) max-age) value) value)))))
    (unless (equal text (gethash key react--storage))
      (puthash key text react--storage)
      (react--emit "tell" "storage-set" (list :key key :value text))))
  value)

(defun react-storage-remove (key)
  "Remove KEY from the page's localStorage."
  (when (gethash key react--storage)
    (remhash key react--storage)
    (react--emit "tell" "storage-remove" (list :key key)))
  nil)

;;;; For tests and debugging

(defun react-reset ()
  "Forget everything that is mounted."
  (setq react--next-dom-id 0 react--ops nil react--dirty nil react--did-mount nil
        react--did-update nil react--effects nil react--next-request 0)
  (clrhash react--hosts)
  (clrhash react--roots)
  (clrhash react--requests)
  (clrhash react--storage)
  (clrhash react--storage-watchers)
  (clrhash react--queries)
  (setq react--location nil react--location-watchers nil react--locale nil)
  (setq react--warned-invalid nil react--warned-tags nil)
  nil)

(defconst react--void-tags
  '(area base br col embed hr img input link meta source track wbr)
  "HTML elements that have no end tag.")

(defun react--escape (text &optional attribute)
  "TEXT with & < > (and \" in an ATTRIBUTE value) written as entities."
  (let ((text (replace-regexp-in-string "&" "&amp;" text t t)))
    (setq text (replace-regexp-in-string "<" "&lt;" text t t)
          text (replace-regexp-in-string ">" "&gt;" text t t))
    (if attribute (replace-regexp-in-string "\"" "&quot;" text t t) text)))

(defun react--html (mounted)
  (cond ((react--text-p mounted) (react--escape (react--text-text mounted)))
        ((react--instance-p mounted) (react--html (react--instance-child mounted)))
        ((react--fragment-p mounted) (mapconcat #'react--html (react--fragment-children mounted) ""))
        (t (let ((attributes "") (plist (react--host-props mounted))
                 (tag (react--host-tag mounted)))
             (while plist
               (let* ((key (car plist))
                      (value (and (not (react--event-name key)) (not (memq key '(:key :ref :inner-html)))
                                  (react--attribute-value key (cadr plist)))))
                 (when value
                   (setq attributes (concat attributes " " (substring (symbol-name key) 1)
                                            (if (eq value t) ""
                                              (format "=\"%s\"" (react--escape (react--valid-text value) t)))))))
               (setq plist (cddr plist)))
             (if (memq tag react--void-tags)
                 (format "<%s%s>" tag attributes)
               (format "<%s%s>%s</%s>" tag attributes
                       (mapconcat #'react--html (react--host-children mounted) "")
                       tag))))))

(defun react-inspect (&optional selector)
  "The mounted components (at SELECTOR, or all of them), parents first:
a list of (:component NAME :depth N :props PROPS :state STATE).  For a
look from outside, as elisp-studio's evaluation gives one."
  (let (out)
    (react--each-instance
     (lambda (instance)
       (push (list :component (react--instance-type instance) :depth (react--instance-depth instance)
                   :props (react--instance-props instance) :state (react--instance-state instance))
             out))
     (and selector (gethash selector react--roots)))
    (nreverse out)))

(defun react-html (selector)
  "What is mounted at SELECTOR, as HTML text (after pending renders).
Text and attribute values are escaped."
  (react--render-dirty)
  (let ((root (gethash selector react--roots)))
    (and root (react--html root))))

(defun react-render-to-string (element)
  "ELEMENT rendered as HTML text, without a page: for a server that sends
a page's first screen (crawlers, link previews, a fast first paint), in
a native Emacs as well as in the page's.  Components render with their
initial state; :did-mount and the like do not run, and nothing is left
mounted.  Text and attribute values are escaped; :inner-html is left
out (there is no HTML cleaner in Lisp)."
  (let ((react--next-dom-id 0) (react--ops nil)
        (react--hosts (make-hash-table)) (react--roots (make-hash-table :test #'equal))
        (react--dirty nil) (react--did-mount nil) (react--did-update nil) (react--effects nil)
        (react--requests (make-hash-table)) (react--next-request 0))
    (react--html (react--mount element 0))))

(provide 'react)
;;; react.el ends here
