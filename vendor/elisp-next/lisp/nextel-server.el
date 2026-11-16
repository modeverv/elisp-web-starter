;;; nextel-server.el --- files as API routes, for server.el  -*- lexical-binding: t; -*-

;; Copyright (c) 2026 modeverv
;; SPDX-License-Identifier: MIT
;; This file is part of elisp-next: https://github.com/modeverv/elisp-next

;; server.el:
;;
;;   (declare-function nextel-server-load "nextel-server")
;;   (load (expand-file-name "vendor/elisp-next/lisp/nextel-server.el" app-server-project-directory) nil t)
;;   (nextel-server-load)
;;
;; loads nextel-schema.el and nextel-route.el, the files of shared/ (the types
;; that the page loads too), the helpers of api/ (files and directories
;; whose name starts with _), and then every other file of api/ as a
;; route: api/feed.el is /api/feed, api/later/[id].el is /api/later/ID.
;; The server reads the directory itself, so a new file is a new route at
;; the next start.  In such a file, `nextel-handle' says what a method does:
;;
;;   (nextel-handle "POST"
;;     :accepts 'parens-later-entry          ; the body, checked
;;     :returns '(list-of parens-later-entry) ; the answer, checked
;;     :handler (lambda (request) ...))
;;
;; REQUEST is a plist (:method :path :params :body): :params are the
;; [names] of the route, :body the data the page sent (read with
;; `app-server-data', never evaluated).  The query is
;; (app-server-parameter NAME).  A body that is not of :accepts is refused
;; (400, with the field that is wrong); an answer that is not of :returns
;; is the server's mistake (500, and the log says which field).  A handler
;; may refuse (`app-server-refuse') and answer later (`app-server-defer').
;;
;; A path is answered by the most specific file whose pattern it matches
;; (api/things/new.el before api/things/[id].el); a method that file does
;; not handle is 405.  Hidden files and directories (an Emacs lock file,
;; .#later.el, while a buffer has unsaved changes) are left out, as the
;; routes writer leaves them out.
;;
;; The same files run in elisp-studio's tab, which has a copy of the
;; project's text files in `app-server-project-directory'.
;;
;; A process that answers one request and ends (a CGI: elisp-studio's
;; serve-cgi.el sets `app-server-single-request') loads only the file that
;; answers it: the patterns come from the file names, so the others are
;; not read.  Anywhere else every route is loaded at the start, so that a
;; mistake in one shows at once; `nextel-server-lazy' chooses.  A file's
;; .elc, when it is newer, is loaded instead of it, here and for
;; nextel-schema.el and nextel-route.el (compiled where the project is
;; deployed: elisp-studio's server/cgi/install.sh).

;;; Code:

(require 'cl-lib)

;; elisp-studio's lisp/app-server.el, which serve-project.el and the
;; studio's tab load before server.el.
(defvar app-server-project-directory)
(defvar app-server-single-request)
(declare-function app-server-data "app-server")
(declare-function app-server-refuse "app-server")
(declare-function app-server-defer "app-server")
(declare-function app-server--deferred-p "app-server")
(declare-function app-server--deferred-function "app-server")

(defconst nextel-server--here (file-name-directory (or load-file-name buffer-file-name default-directory))
  "The directory of nextel-server.el, where its companions are.")

(defun nextel-server--load (file)
  "Load FILE, or its .elc when that is newer."
  (let ((compiled (concat file "c")))
    (load (if (file-newer-than-file-p compiled file) compiled file) nil t t)))

(nextel-server--load (expand-file-name "nextel-schema.el" nextel-server--here))
(nextel-server--load (expand-file-name "nextel-route.el" nextel-server--here))
(declare-function nextel-match "nextel-route")
(declare-function nextel-pattern-of-file "nextel-route")
(declare-function nextel-pattern< "nextel-route")
(declare-function nextel-check "nextel-schema")

(defvar nextel-server-routes nil
  "((PATTERN METHOD . SPEC) ...), in the order they are tried: those of
the files loaded so far.")
(defvar nextel-server-lazy nil
  "Non-nil: load a file of api/ when a request first needs it, not at the
start.  Also when `app-server-single-request' is non-nil.")
(defvar nextel-server--files nil
  "((PATTERN . FILE) ...): the route files of api/, most specific first.")
(defvar nextel-server--loaded nil "The route files loaded.")
(defvar nextel-server--loading nil "The pattern of the api/ file being loaded.")

(defun nextel-handle (method &rest spec)
  "In a file of api/: answer METHOD (\"GET\", \"POST\" ...) at its route.
SPEC: :handler (REQUEST) -> data, :accepts TYPE, :returns TYPE.  See the
commentary of nextel-server.el."
  (unless nextel-server--loading
    (error "nextel-handle belongs in a file of api/, loaded by `nextel-server-load'"))
  (unless (functionp (plist-get spec :handler))
    (error "%s %s has no :handler" method nextel-server--loading))
  (push (cl-list* nextel-server--loading method spec) nextel-server-routes)
  nil)

(defun nextel-server--private-p (relative)
  "Non-nil if RELATIVE (a path under api/) is a helper, not a route."
  (cl-some (lambda (part) (string-prefix-p "_" part)) (split-string relative "/" t)))

(defun nextel-server--lisp-files (directory)
  "The .el files under DIRECTORY, sorted, without hidden files and
directories."
  (and (file-directory-p directory)
       (sort (cl-remove-if (lambda (file)
                             (cl-some (lambda (part) (string-prefix-p "." part))
                                      (split-string (file-relative-name file directory) "/" t)))
                           (directory-files-recursively directory "\\.el\\'"))
             #'string<)))

(defun nextel-server--load-route (entry)
  "Load the route file of ENTRY, (PATTERN . FILE), unless it is loaded."
  (unless (member (cdr entry) nextel-server--loaded)
    (push (cdr entry) nextel-server--loaded)
    (let ((nextel-server-routes nil))
      (let ((nextel-server--loading (car entry)))
        (nextel-server--load (cdr entry)))
      (setq entry (nreverse nextel-server-routes)))
    (setq nextel-server-routes
          (sort (append nextel-server-routes entry) (lambda (a b) (nextel-pattern< (car a) (car b)))))))

(defun nextel-server-load (&optional directory)
  "Load shared/ and api/ of DIRECTORY (the project), and answer /api/ with them.
Returns the routes loaded: all of them, or none when the files of api/
are loaded as requests need them (`nextel-server-lazy')."
  (let* ((root (file-name-as-directory
                (expand-file-name (or directory (and (boundp 'app-server-project-directory) app-server-project-directory)
                                      default-directory))))
         (shared (expand-file-name "shared/" root))
         (api (expand-file-name "api/" root))
         (files (nextel-server--lisp-files api)))
    (dolist (file (nextel-server--lisp-files shared))
      (nextel-server--load file))
    (setq nextel-server-routes nil nextel-server--loaded nil nextel-server--files nil)
    (dolist (file files)
      (if (nextel-server--private-p (file-relative-name file api))
          (nextel-server--load file)
        (push (cons (nextel-pattern-of-file (file-relative-name file root)) file) nextel-server--files)))
    ;; A stable sort: of two files with one pattern, the first in the alphabet first.
    (setq nextel-server--files
          (sort (nreverse nextel-server--files) (lambda (a b) (nextel-pattern< (car a) (car b)))))
    (unless (or nextel-server-lazy (bound-and-true-p app-server-single-request))
      (mapc #'nextel-server--load-route nextel-server--files))
    (defalias 'app-server-handle #'nextel-server-handle)
    nextel-server-routes))

(defun nextel-server--checked (answer returns what)
  "ANSWER (data, or what `app-server-defer' returned), checked against RETURNS."
  (cond
   ((null returns) answer)
   ;; An answer that comes later is checked when it comes.
   ((and (fboundp 'app-server--deferred-p) (app-server--deferred-p answer))
    (let ((function (app-server--deferred-function answer)))
      (app-server-defer
       (lambda (respond fail)
         (funcall function
                  (lambda (data)
                    (condition-case failure
                        (funcall respond (nextel-check returns data what))
                      (nextel-type-error
                       (message "nextel-server: %s answered wrongly: %s" what (cadr failure))
                       (funcall fail (format "The server's answer is wrong: %s" (cadr failure)) 500))))
                  fail)))))
   (t (condition-case failure
          (nextel-check returns answer what)
        (nextel-type-error
         (message "nextel-server: %s answered wrongly: %s" what (cadr failure))
         (app-server-refuse (format "The server's answer is wrong: %s" (cadr failure)) 500))))))

(defun nextel-server-handle (method path body)
  "Answer METHOD at PATH with the route of api/ that it matches.
The most specific pattern that matches PATH answers; a METHOD that its
file does not handle is 405, also when a less specific file would."
  ;; The files in the order their patterns are tried: the first that
  ;; matches and handles anything at all is the most specific.
  (let ((pattern nil)
        (files nextel-server--files))
    (while (and files (not pattern))
      (let ((entry (pop files)))
        (when (nextel-match (car entry) path)
          ;; Every file of that pattern (api/feed.el and api/feed/index.el).
          (dolist (same (cons entry (cl-remove-if-not (lambda (other) (equal (car other) (car entry))) files)))
            (nextel-server--load-route same))
          (when (assoc (car entry) nextel-server-routes)
            (setq pattern (car entry))))))
    (unless pattern
      (signal 'file-missing (list "No such API" path)))
    (let ((route (cl-find-if (lambda (route) (and (equal (car route) pattern) (equal (cadr route) method)))
                             nextel-server-routes)))
      (unless route
        (app-server-refuse (format "%s is not allowed at %s" method path) 405))
      (let* ((pattern (car route))
             (spec (cddr route))
             (params (nextel-match pattern path))
             (what (format "%s %s" method pattern))
             (data (app-server-data body))
             (accepts (plist-get spec :accepts)))
        (when accepts
          (condition-case failure
              (nextel-check accepts data "body")
            (nextel-type-error (app-server-refuse (cadr failure) 400))))
        (nextel-server--checked
         (funcall (plist-get spec :handler)
                  (list :method method :path path :params (and (listp params) params) :body data))
         (plist-get spec :returns)
         what)))))

(provide 'nextel-server)
;;; nextel-server.el ends here
