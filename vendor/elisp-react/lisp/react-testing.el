;;; react-testing.el --- test an elisp-react application without a browser  -*- lexical-binding: t; -*-

;; Copyright (c) 2026 modeverv
;; SPDX-License-Identifier: MIT

;; A page made of Lisp data, for ERT: it takes the DOM operations that
;; `react-flush' returns, as the browser's host would, and keeps the tree,
;; the attributes, the listeners, and what Lisp asked of the page.  A test
;; renders, finds elements, clicks and types, answers requests, and looks.
;;
;;   (require 'react-testing)
;;   (ert-deftest my-counter ()
;;     (react-testing-render '(Counter (:start 3)))
;;     (react-testing-click (react-testing-find :class "increment"))
;;     (should (equal (react-testing-text (react-testing-find :class "count")) "4")))
;;
;; Run with any Emacs that has react.el and the application on its
;; load-path (`emacs --batch -l react-testing -l app -l app-test -f
;; ert-run-tests-batch-and-exit'), or with the page's own Emacs 30.2 under
;; Node (wasmacs's tools/scripts/ert.mjs).

;;; Code:

(require 'cl-lib)
(require 'react)

(cl-defstruct (react-testing--node (:constructor react-testing--node-create) (:copier nil))
  id tag text attributes properties children parent listeners html)

(defvar react-testing--nodes (make-hash-table) "DOM id -> node.")
(defvar react-testing--roots nil
  "Alist: selector -> the page element it names, a node without a tag
whose children are what is mounted there.")
(defvar react-testing-requests nil
  "What Lisp asked of the page and waits for, oldest first.
Each is (REQUEST COMMAND ARGUMENT).")
(defvar react-testing-told nil "What Lisp told the page: (COMMAND ARGUMENT), oldest first.")
(defvar react-testing-invoked nil "Methods called on nodes: (ID METHOD ARGS...), oldest first.")

;;;; The page

(defun react-testing-reset ()
  "Forget everything: Lisp's side (`react-reset') and the page's."
  (react-reset)
  (clrhash react-testing--nodes)
  (setq react-testing--roots nil react-testing-requests nil react-testing-told nil
        react-testing-invoked nil)
  (react--location-set '(:href "http://localhost/" :pathname "/" :search "" :hash ""))
  (react--locale-set '(:languages ["en"] :timeZone "UTC" :offset 0))
  nil)

(defun react-testing-storage (key value)
  "Have the page's storage hold VALUE (Lisp data) under KEY, as if a
visit before had stored it.  `react-testing-render' and
`react-testing-load' start afresh and forget it, so the order is:
`react-testing-reset', this, then `react-mount' or `load' the
application, then `react-testing-flush'."
  (puthash key (let ((print-length nil) (print-level nil)) (prin1-to-string value)) react--storage)
  nil)

(defun react-testing-location (href)
  "Make HREF the page's address and tell Lisp about it."
  (let* ((hash (and (string-match "#.*\\'" href) (match-string 0 href)))
         (search (and (string-match "\\?[^#]*" href) (match-string 0 href))))
    (react-testing--apply
     (react--location-changed (list :href href :pathname "/" :search (or search "") :hash (or hash ""))))))

(defun react-testing--node (id)
  (or (gethash id react-testing--nodes) (error "react-testing: no node %S" id)))

(defun react-testing--detach (node)
  (let ((parent (react-testing--node-parent node)))
    (when parent
      (setf (react-testing--node-children parent) (delq node (react-testing--node-children parent))
            (react-testing--node-parent node) nil))))

(defun react-testing--forget (node)
  (remhash (react-testing--node-id node) react-testing--nodes)
  (mapc #'react-testing--forget (react-testing--node-children node)))

(defun react-testing--apply (ops)
  "Do what the operations OPS (a vector of vectors) say, as the host would."
  (mapc
   (lambda (op)
     (pcase (append op nil)
       (`("create" ,id ,tag . ,_) (puthash id (react-testing--node-create :id id :tag tag) react-testing--nodes))
       (`("text" ,id ,text) (puthash id (react-testing--node-create :id id :text text) react-testing--nodes))
       (`("set-text" ,id ,text) (setf (react-testing--node-text (react-testing--node id)) text))
       (`("attr" ,id ,name ,value)
        (let ((node (react-testing--node id)))
          (setf (react-testing--node-attributes node)
                (if (memq value '(nil :false))
                    (assoc-delete-all name (react-testing--node-attributes node))
                  (cons (cons name (if (eq value t) "" value)) (assoc-delete-all name (react-testing--node-attributes node)))))))
       (`("prop" ,id ,name ,value)
        (setf (alist-get name (react-testing--node-properties (react-testing--node id)) nil nil #'equal) value))
       (`("listen" ,id ,name . ,rest)
        (setf (alist-get name (react-testing--node-listeners (react-testing--node id)) nil nil #'equal) (or (car rest) t)))
       (`("unlisten" ,id ,name)
        (let ((node (react-testing--node id)))
          (setf (react-testing--node-listeners node) (assoc-delete-all name (react-testing--node-listeners node)))))
       (`("insert" ,parent ,id ,before)
        (let ((parent (react-testing--node parent)) (node (react-testing--node id)))
          (react-testing--detach node)
          (setf (react-testing--node-parent node) parent)
          (let* ((children (react-testing--node-children parent))
                 (at (and before (cl-position (react-testing--node before) children))))
            (setf (react-testing--node-children parent)
                  (if at (append (cl-subseq children 0 at) (list node) (nthcdr at children))
                    (append children (list node)))))))
       (`("before" ,id ,before)
        ;; As the DOM's before(): nothing when BEFORE is in no parent.
        (let* ((node (react-testing--node id)) (before (react-testing--node before))
               (parent (react-testing--node-parent before)))
          (when parent
            (react-testing--detach node)
            (let* ((children (react-testing--node-children parent))
                   (at (cl-position before children)))
              (setf (react-testing--node-children parent)
                    (append (cl-subseq children 0 at) (list node) (nthcdr at children))
                    (react-testing--node-parent node) parent)))))
       (`("replace" ,old ,id)
        (let* ((old (react-testing--node old)) (node (react-testing--node id))
               (parent (react-testing--node-parent old)))
          (react-testing--detach node)
          (when parent
            (setf (react-testing--node-children parent)
                  (cl-substitute node old (react-testing--node-children parent)))
            (setf (react-testing--node-parent node) parent (react-testing--node-parent old) nil))
          (react-testing--forget old)))
       (`("remove" ,id)
        (let ((node (react-testing--node id)))
          (react-testing--detach node)
          (react-testing--forget node)))
       (`("mount" ,selector . ,ids)
        (let ((container (or (cdr (assoc selector react-testing--roots))
                             (let ((new (react-testing--node-create)))
                               (push (cons selector new) react-testing--roots)
                               new)))
              (nodes (mapcar #'react-testing--node ids)))
          (unless (eq (react-testing--node-parent (car nodes)) container)
            (dolist (child (react-testing--node-children container))
              (setf (react-testing--node-parent child) nil))
            (mapc #'react-testing--detach nodes)
            (dolist (node nodes) (setf (react-testing--node-parent node) container))
            (setf (react-testing--node-children container) nodes))))
       (`("html" ,id ,html) (setf (react-testing--node-html (react-testing--node id)) html))
       (`("invoke" ,id ,method . ,args) (setq react-testing-invoked (append react-testing-invoked (list (cl-list* id method args)))))
       (`("call" ,request ,command ,argument)
        (setq react-testing-requests (append react-testing-requests (list (list request command argument)))))
       (`("tell" ,command ,argument)
        (setq react-testing-told (append react-testing-told (list (list command argument)))))
       (`("cancel" ,request) (setq react-testing-requests (cl-remove request react-testing-requests :key #'car)))
       (other (error "react-testing: unknown operation %S" other))))
   ops)
  nil)

(defun react-testing-render (element &optional selector)
  "Start afresh and render ELEMENT at SELECTOR (default \"#app\").
Returns the root component instance, if ELEMENT is a component."
  (react-testing-reset)
  (react-mount element (or selector "#app"))
  (react-testing-flush)
  (react-root (or selector "#app")))

(defun react-testing-load (file)
  "Start afresh and load FILE, an application that mounts itself."
  (react-testing-reset)
  (load file nil t)
  (react-testing-flush))

(defun react-testing-flush ()
  "Apply what Lisp has to say to the page now (pending renders)."
  (react-testing--apply (react-flush)))

;;;; Finding

(defun react-testing--all (&optional selector)
  (let (out)
    (cl-labels ((walk (node) (push node out) (mapc #'walk (react-testing--node-children node))))
      (dolist (root react-testing--roots)
        (when (or (null selector) (equal (car root) selector)) (walk (cdr root)))))
    (nreverse out)))

(defun react-testing-text (id)
  "The text of the node ID and everything in it."
  (let ((node (react-testing--node id)))
    (or (react-testing--node-text node)
        (react-testing--node-html node)
        (mapconcat (lambda (child) (react-testing-text (react-testing--node-id child)))
                   (react-testing--node-children node) ""))))

(defun react-testing-attribute (id name)
  "The attribute NAME of the node ID, or nil."
  (cdr (assoc name (react-testing--node-attributes (react-testing--node id)))))

(defun react-testing-property (id name)
  "The DOM property NAME (\"value\", \"checked\" ...) Lisp set on the node ID."
  (cdr (assoc name (react-testing--node-properties (react-testing--node id)))))

(defun react-testing--match-p (node tag class text attribute)
  (and (react-testing--node-tag node)
       (or (null tag) (equal (react-testing--node-tag node) (format "%s" tag)))
       (or (null class)
           (member class (split-string (or (cdr (assoc "class" (react-testing--node-attributes node))) ""))))
       (or (null text) (equal (react-testing-text (react-testing--node-id node)) text))
       (or (null attribute)
           (equal (cdr (assoc (car attribute) (react-testing--node-attributes node))) (cadr attribute)))))

(cl-defun react-testing-find-all (&key tag class text attribute selector)
  "The ids of the elements that match, in document order: TAG (a symbol
or string), CLASS (one of its classes), TEXT (its whole text), ATTRIBUTE
\(NAME VALUE).  SELECTOR limits it to one root."
  (mapcar #'react-testing--node-id
          (cl-remove-if-not (lambda (node) (react-testing--match-p node tag class text attribute))
                            (react-testing--all selector))))

(cl-defun react-testing-find (&rest criteria &key tag class text attribute selector)
  "The id of the first element that matches CRITERIA (see
`react-testing-find-all'); an error if there is none."
  (ignore tag class text attribute selector)
  (or (car (apply #'react-testing-find-all criteria))
      (error "react-testing: no element matches %S" criteria)))

(defun react-testing-html (&optional selector)
  "The page (at SELECTOR, default \"#app\") as HTML, for a quick look."
  (let ((root (cdr (assoc (or selector "#app") react-testing--roots))))
    (and root (mapconcat #'react-testing--html (react-testing--node-children root) ""))))

(defun react-testing--html (node)
  (if (react-testing--node-text node)
      (react-testing--node-text node)
    (format "<%s%s>%s</%s>" (react-testing--node-tag node)
            (mapconcat (lambda (attribute) (format " %s=\"%s\"" (car attribute) (cdr attribute)))
                       (reverse (react-testing--node-attributes node)) "")
            (or (react-testing--node-html node) (mapconcat #'react-testing--html (react-testing--node-children node) ""))
            (react-testing--node-tag node))))

;;;; Doing

(defun react-testing-dispatch (id name &optional event)
  "The event NAME happens on the node ID, with the plist EVENT: it goes
up through the listeners of the node and its parents, as in a browser,
until one stops it (`react-handler' :stop)."
  (let ((node (react-testing--node id))
        (event (append event (list :type name :target id))))
    (catch 'stop
      (while node
        (let ((options (cdr (assoc name (react-testing--node-listeners node)))))
          (when (and options
                     (or (not (consp options)) (not (plist-get options :self)) (eq (react-testing--node-id node) id))
                     (or (not (consp options)) (not (plist-get options :keys)) (member (plist-get event :key) (append (plist-get options :keys) nil))))
            (react-testing--apply (react-dispatch-event (react-testing--node-id node) name event))
            (when (and (consp options) (plist-get options :stop)) (throw 'stop nil))))
        (setq node (react-testing--node-parent node)))))
  nil)

(defun react-testing-click (id)
  "Click the node ID."
  (react-testing-dispatch id "click"))

(defun react-testing-input (id value)
  "Type VALUE into the input ID: an input event, then a change event."
  (setf (alist-get "value" (react-testing--node-properties (react-testing--node id)) nil nil #'equal) value)
  (react-testing-dispatch id "input" (list :value value))
  (react-testing-dispatch id "change" (list :value value)))

(defun react-testing-key (id key)
  "Press KEY (\"Enter\", \"a\") in the node ID: a keydown event."
  (react-testing-dispatch id "keydown" (list :key key)))

(defun react-testing-submit (id)
  "Submit the form ID, with its fields: the named inputs in it."
  (let (fields)
    (cl-labels ((walk (node)
                  (let ((name (cdr (assoc "name" (react-testing--node-attributes node)))))
                    (when name
                      (push (vector name (or (cdr (assoc "value" (react-testing--node-properties node)))
                                             (cdr (assoc "value" (react-testing--node-attributes node))) ""))
                            fields)))
                  (mapc #'walk (react-testing--node-children node))))
      (walk (react-testing--node id)))
    (react-testing-dispatch id "submit" (list :form (vconcat (nreverse fields))))))

(defun react-testing-answer (command value &optional ok)
  "Answer the oldest waiting request for COMMAND (\"fetch\", \"timeout\"
...) with VALUE, successfully unless OK is :fail.  Returns its argument."
  (let ((request (cl-find command react-testing-requests :key #'cadr :test #'equal)))
    (unless request (error "react-testing: nothing waits for %s" command))
    (setq react-testing-requests (delq request react-testing-requests))
    (react-testing--apply (react-host-reply (car request) (not (eq ok :fail)) value))
    (nth 2 request)))

(defun react-testing-answer-fetch (status text)
  "Answer the oldest waiting fetch with STATUS and the body TEXT.
Returns the fetch's argument, (:url ... :method ...)."
  (react-testing-answer "fetch" (list :status status :ok (and (< status 400) t) :text text :headers nil)))

(defun react-testing-time-passes ()
  "Fire every waiting timeout once (and every interval once)."
  (dolist (request react-testing-requests)
    (when (member (cadr request) '("timeout" "interval"))
      (when (equal (cadr request) "timeout") (setq react-testing-requests (delq request react-testing-requests)))
      (react-testing--apply (react-host-reply (car request) t nil)))))

(provide 'react-testing)
;;; react-testing.el ends here
