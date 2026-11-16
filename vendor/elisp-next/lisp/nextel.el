;;; nextel.el --- files as pages: a Next.js-like layer over elisp-react  -*- lexical-binding: t; -*-

;; Copyright (c) 2026 modeverv
;; SPDX-License-Identifier: MIT
;; This file is part of elisp-next: https://github.com/modeverv/elisp-next

;; A page is a file.  pages/index.el is "/", pages/watch.el is "/watch",
;; pages/channel/[id].el is "/channel/ID", with the parameter :id.  The
;; file says what its page is with `nextel-page', which is
;; `react-define-component' with a few more keys:
;;
;;   ;;; pages/channel/[id].el
;;   (nextel-page ChannelPage
;;     :load (lambda (route) (parens-load-channel (nextel-param route :id)))
;;     :head (lambda (route data) (list :title (plist-get data :title)))
;;     :render (lambda (self)
;;               (jsx (h1 (plist-get (nextel-data self) :title)))))
;;
;; - :load gets the route and returns an awaitable, a function of RESOLVE
;;   and REJECT (`nextel-request', not a `react-async' task); the page
;;   renders when it has answered, with the value as (nextel-data SELF).
;;   Meanwhile :loading, after a failure :error (or the defaults,
;;   `nextel-loading-function' and `nextel-error-function').  The answers are
;;   kept by route (`react-query'): going back shows them at once, and loads
;;   them again in the background when they are older than
;;   `nextel-stale-ms'.
;; - :head gives the document's :title, :description and other :meta.
;; - The page gets the props :route, a plist (:page :pattern :path
;;   :params :query), and :data.  `nextel-param' and `nextel-query' read it.
;;
;; Around every page is the layout of pages/_layout.el (`nextel-layout'),
;; which stays mounted from one page to the next and gets the page as its
;; :children; pages/404.el is the page of an address that no file has.
;;
;; nextel-build.el reads pages/ and writes routes.el (which page is
;; which pattern) and the <script> tags in index.html, in the Emacs you
;; edit with (elisp-studio's too): M-x nextel-write-routes after adding,
;; removing or renaming a page, or M-x nextel-routes-mode to do it at
;; every save; bin/nextel-routes in batch.  elisp-studio reloads a page
;; file that was saved, as any other file, and keeps the state.
;;
;; The address is in the hash by default (#/watch?v=ID): that works on any
;; static host and in elisp-studio's preview.  `nextel-url-mode' `path' puts
;; it in the path (/watch?v=ID); a server then has to send index.html for
;; every route.
;;
;; Links: (Link (:href (nextel-href "/watch" :v id) :class "card") ...).
;; Going somewhere from Lisp: (nextel-go "/results" :search_query text).
;; Asking the server: (nextel-request "GET" "/api/videos/[id]" :id id
;; :returns \\='parens-video), checked against the type that the server
;; checks too (nextel-schema.el, shared/).

;;; Code:

(require 'cl-lib)
(require 'subr-x)
(require 'react)
(require 'nextel-schema)
(require 'nextel-route)

(defvar nextel-url-mode 'hash
  "Where the route is in the address: `hash' (#/watch?v=ID) or `path'.")
(defvar nextel-base-path ""
  "In the `path' mode, the path under which the application is (\"/app\").")
(defvar nextel-routes nil
  "((PATTERN . PAGE) ...), in the order they are tried (routes.el).")
(defvar nextel-layout nil "The layout component around every page, or nil.")
(defvar nextel-not-found nil "The page of an address that no page has, or nil.")
(defvar nextel-stale-ms 60000
  "How long, in milliseconds, a page's loaded data counts as fresh.
Coming to an address whose data is older loads it again in the
background; the page shows the data it has meanwhile.  nil: never (then
only `nextel-reload' and a retry load data again).")
(defvar nextel-loading-function (lambda (_route) "")
  "The element shown while a page without :loading loads: (ROUTE).")
(defvar nextel-error-function
  (lambda (_route error retry)
    (list 'div '(:class "nextel-error")
          (list 'p nil (format "%s" (or (plist-get error :message) error)))
          (list 'button (list :type "button" :on-click (lambda (_event) (funcall retry))) "Retry")))
  "The element shown when the :load of a page without :error failed:
\(ROUTE ERROR RETRY), RETRY a function that loads again.")
(defvar nextel-title-function (lambda (title) (or title ""))
  "The document's title for a page whose :head says TITLE (nil: none).")
(defvar nextel-navigate-functions nil
  "Functions of a ROUTE, run after the page of a new address rendered.")
(defvar nextel-page-props-function nil
  "A function of ROUTE: props that every page gets besides :route and
:data (what the whole application knows, its language, say).  After it
changed, `nextel-refresh'.")
(defvar nextel--route nil "The route on the page now.")

;;;; Routes

(defun nextel-define-routes (routes &rest options)
  "Take ROUTES, ((PATTERN . PAGE) ...), with OPTIONS :layout and :not-found.
routes.el, which nextel-build.el writes, calls this."
  (setq nextel-routes (sort (copy-sequence routes) (lambda (a b) (nextel-pattern< (car a) (car b))))
        nextel-layout (plist-get options :layout)
        nextel-not-found (plist-get options :not-found)))

(defun nextel-resolve (path &optional search)
  "The route of PATH (\"/watch\") and the query string SEARCH: a plist
\(:page PAGE :pattern PATTERN :path PATH :params PLIST :query ALIST).
:page is `nextel-not-found' (and :pattern nil) when no route matches."
  (let ((query (react-url-query (or search ""))))
    (or (cl-loop for (pattern . page) in nextel-routes
                 for params = (nextel-match pattern path)
                 when params
                 return (list :page page :pattern pattern :path path
                              :params (and (listp params) params) :query query))
        (list :page nextel-not-found :pattern nil :path path :params nil :query query))))

(defun nextel--location-route (location)
  "The route that LOCATION (`react-location') shows."
  (if (eq nextel-url-mode 'path)
      (let ((path (plist-get location :pathname)))
        (when (string-prefix-p nextel-base-path path)
          (setq path (substring path (length nextel-base-path))))
        (nextel-resolve (if (string-empty-p path) "/" path) (plist-get location :search)))
    (let* ((hash (string-remove-prefix "#" (or (plist-get location :hash) "")))
           (question (string-search "?" hash))
           (path (if question (substring hash 0 question) hash)))
      (nextel-resolve (if (string-empty-p path) "/" path) (and question (substring hash question))))))

(defun nextel--route (thing)
  "THING, a route, or the route of THING, a page component instance."
  (if (and (consp thing) (keywordp (car thing))) thing (react-props thing :route)))

(defun nextel-route ()
  "The route of the page shown now."
  nextel--route)

(defun nextel-param (thing key)
  "The parameter KEY (:id) of the route of THING, a page or a route."
  (plist-get (plist-get (nextel--route thing) :params) key))

(defun nextel-query (thing name)
  "The value of NAME in the query of the route of THING, or nil."
  (cdr (assoc name (plist-get (nextel--route thing) :query))))

(defun nextel-data (self)
  "What the :load of the page SELF answered."
  (react-props self :data))

;;;; Addresses

(defun nextel-href (pattern &rest params)
  "The address of the page PATTERN with PARAMS, for a link.
  (nextel-href \"/channel/[id]\" :id \"UCx\")  =>  \"#/channel/UCx\"
  (nextel-href \"/watch\" :v \"abc\" :t 30)     =>  \"#/watch?v=abc&t=30\""
  (let ((path (nextel-fill pattern params)))
    (if (eq nextel-url-mode 'path) (concat nextel-base-path path) (concat "#" path))))

(defun nextel-navigate (href &optional replace)
  "Go to HREF (`nextel-href'): a new entry in the history, or with REPLACE
instead of the current one.  The router hears it and shows the page."
  (react-navigate href replace))

(defun nextel-go (pattern &rest params)
  "Go to the page PATTERN with PARAMS (see `nextel-href')."
  (nextel-navigate (apply #'nextel-href pattern params)))

(defun nextel--without (plist keys)
  (cl-loop for (key value) on plist by #'cddr
           unless (memq key keys) append (list key value)))

(react-define-component 'Link
  :render
  (lambda (self)
    ;; In the hash mode a link is an <a> that the browser follows (and
    ;; elisp-react hears).  In the path mode it would load the page anew:
    ;; Lisp goes there itself.
    (let* ((props (react-props self))
           (href (plist-get props :href))
           (attributes (nextel--without props '(:children :key))))
      (cl-list* 'a
                (if (eq nextel-url-mode 'path)
                    (append attributes
                            (list :on-click (react-handler (lambda (_event) (nextel-navigate href)) :prevent t)))
                  attributes)
                (plist-get props :children)))))

;;;; Pages

(defmacro nextel-page (name &rest spec)
  "Define the page NAME: `react-define-component' with SPEC, and also
:load (ROUTE) -> an awaitable, :head (ROUTE DATA) -> (:title :description
:meta ((NAME . CONTENT) ...)), :loading (ROUTE) -> an element, :error
\(ROUTE ERROR RETRY) -> an element.  See the commentary of nextel.el."
  (declare (indent 1))
  (let ((keys '(:load :head :loading :error)))
    `(progn
       (put ',name 'nextel-page
            (list ,@(cl-loop for key in keys
                             when (plist-member spec key) append (list key (plist-get spec key)))))
       (react-define-component ',name ,@(nextel--without spec keys)))))

(defmacro nextel-layout (name &rest spec)
  "Define the layout NAME, around every page: `react-define-component'
with SPEC.  It gets the props :route and :children (the page)."
  (declare (indent 1))
  `(react-define-component ',name ,@spec))

(defun nextel--query-key (route)
  (list 'nextel (plist-get route :page) (plist-get route :params) (plist-get route :query)))

(defun nextel--head (self route spec status data)
  "Give the document the title and meta of ROUTE's page, after the render."
  (let* ((head-function (plist-get spec :head))
         (head (and head-function (or (not (plist-get spec :load)) (eq status 'success))
                    (funcall head-function route data)))
         (title (funcall nextel-title-function (plist-get head :title)))
         (meta (append (and (plist-get head :description) (list (cons "description" (plist-get head :description))))
                       (plist-get head :meta))))
    (react-effect self 'nextel-head (cons title meta)
      (lambda ()
        (react-set-title title)
        (dolist (entry meta) (react-set-meta (car entry) (cdr entry)))
        nil))))

(defvar nextel--loaded-at (make-hash-table :test #'equal)
  "When the data under each key of a page was loaded, a `float-time'.")
(defvar nextel--arrived nil
  "The key of the address that the router rendered last.")

(defun nextel--timed (key awaitable)
  "AWAITABLE, noting in `nextel--loaded-at' when it answered under KEY."
  (lambda (resolve reject)
    (funcall awaitable
             (lambda (data) (puthash key (float-time) nextel--loaded-at) (funcall resolve data))
             reject)))

(defun nextel--arrive (key)
  "At a new address, whose data is under KEY: load it again if it is stale.
`react-query' looks at the age of data only when a component reads a key
for the first time, and the router keeps reading every key it has read."
  (unless (equal key nextel--arrived)
    (setq nextel--arrived key)
    (let ((loaded (gethash key nextel--loaded-at)))
      (when (and loaded nextel-stale-ms
                 (> (* 1000 (- (float-time) loaded)) nextel-stale-ms))
        (react-invalidate key)))))

(defun nextel--page-element (self route)
  "The element of ROUTE's page, or what to show while it loads or failed."
  (let* ((page (plist-get route :page))
         (spec (and page (get page 'nextel-page)))
         (load (plist-get spec :load))
         (key (progn (nextel--arrive (nextel--query-key route)) (nextel--query-key route)))
         (state (and load
                     (react-query self key (lambda () (nextel--timed key (funcall load route)))
                                  :stale-ms (or nextel-stale-ms 0))))
         (status (plist-get state :status)))
    (nextel--head self route spec status (plist-get state :data))
    (cond ((null page) "")
          ;; Loading, or loading again after a failure (a retry).
          ((and load (or (eq status 'loading) (and (eq status 'error) (plist-get state :fetching))))
           (funcall (or (plist-get spec :loading) nextel-loading-function) route))
          ((and load (eq status 'error))
           (funcall (or (plist-get spec :error) nextel-error-function)
                    route (plist-get state :error) (lambda () (react-invalidate key))))
          (t (list page (append (list :key page :route route :data (plist-get state :data))
                                (and nextel-page-props-function (funcall nextel-page-props-function route))))))))

(react-define-component 'nextel-router
  :initial-state (lambda (_props)
                   (setq nextel--arrived nil)
                   (list :location (react-location)))
  :render
  (lambda (self)
    (react-effect self 'nextel-location nil
      (lambda ()
        (let ((watch (react-location-watch (lambda (location) (react-set-state self :location location)))))
          (lambda () (react-location-unwatch watch)))))
    (let* ((route (nextel--location-route (react-state self :location)))
           (page (nextel--page-element self route)))
      (setq nextel--route route)
      (react-effect self 'nextel-navigated (list (plist-get route :path) (plist-get route :query))
        ;; Not `run-hook-with-args': the page's Emacs (wasmacs's eval
        ;; service) runs no hooks, it returns at once.
        (lambda () (dolist (function nextel-navigate-functions) (funcall function route)) nil))
      (if nextel-layout (list nextel-layout (list :route route) page) page))))

(defun nextel-start (selector)
  "Show the application at SELECTOR: the router, the layout, the pages.
routes.el calls this last."
  (react-mount '(nextel-router) selector))

(defun nextel-refresh ()
  "Render the page again, with what `nextel-page-props-function' says now."
  (react-refresh 'nextel-router))

(defun nextel-reload ()
  "Load every page's data again (after the source of the data changed)."
  (react-invalidate '(nextel)))

;;;; The server

(defun nextel--api-url (pattern params)
  (let ((path (nextel-fill pattern params)))
    ;; In the hash mode the document's address is the application's
    ;; directory: a relative address reaches its server under any path
    ;; (GitHub Pages' /NAME/), and elisp-studio's preview takes it too.
    (if (eq nextel-url-mode 'path) (concat nextel-base-path path) (substring path 1))))

(defun nextel-request (method pattern &rest options)
  "An awaitable: what the API route PATTERN answers to METHOD, Lisp data.
PATTERN is an address of api/ (\"/api/videos/[id]\"); OPTIONS give its
[names] and the query, and:
  :body DATA      sent printed; with :sends TYPE checked first
  :returns TYPE   the answer is checked: a wrong one fails the request
A failure is (:status N :message TEXT); :status is nil when the answer
was there but not of TYPE, or there was no answer."
  (let* ((body (plist-get options :body))
         (sends (plist-get options :sends))
         (returns (plist-get options :returns))
         (url (nextel--api-url pattern (nextel--without options '(:body :sends :returns))))
         (what (format "%s %s" method pattern)))
    (when sends (nextel-check sends body (format "%s body" what)))
    (lambda (resolve reject)
      (react-fetch url
                   :method method
                   :body (and (plist-member options :body)
                              (let ((print-length nil) (print-level nil)) (prin1-to-string body)))
                   :then (lambda (response)
                           (let ((data (condition-case nil (car (read-from-string (plist-get response :text)))
                                         (error nil))))
                             (if (not (plist-get response :ok))
                                 (funcall reject (list :status (plist-get response :status)
                                                       :message (if (stringp data) data
                                                                  (format "HTTP %s" (plist-get response :status)))))
                               (condition-case failure
                                   (funcall resolve (if returns (nextel-check returns data what) data))
                                 (nextel-type-error (funcall reject (list :status nil :message (cadr failure))))))))
                   :catch (lambda (message) (funcall reject (list :status nil :message message)))))))

(provide 'nextel)
;;; nextel.el ends here
