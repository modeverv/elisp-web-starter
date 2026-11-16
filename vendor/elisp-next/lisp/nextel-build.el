;;; nextel-build.el --- write the routes from pages/, in Emacs  -*- lexical-binding: t; -*-

;; Copyright (c) 2026 modeverv
;; SPDX-License-Identifier: MIT
;; This file is part of elisp-next: https://github.com/modeverv/elisp-next

;; The page loads its Lisp from <script> tags and cannot list a directory,
;; so which file is which address has to be written down: routes.el at the
;; project's root (the patterns and their pages) and the page's <script> tags in
;; index.html.  This file writes them, in the Emacs you edit with: the
;; one in elisp-studio's page, your own, or one in batch.
;;
;;   M-x load-file RET vendor/elisp-next/lisp/nextel-build.el RET   once
;;   M-x nextel-write-routes     after adding, removing or renaming a page
;;   M-x nextel-routes-mode      write them at every save of a file of
;;                               pages/, api/ or shared/ (a new page is
;;                               there as soon as it is saved)
;;
;; In batch (bin/nextel-routes, for npm and CI), in the project:
;;
;;   emacs --batch -l vendor/elisp-next/lisp/nextel-build.el -f nextel-write-routes
;;   ... -f nextel-check-routes   exit 1 when they are not up to date
;;   ... -f nextel-watch-routes   write them whenever the files change
;;
;; What it reads: pages/**.el, each naming its component with
;; (nextel-page NAME ...); pages/_layout.el with (nextel-layout NAME ...);
;; pages/404.el.  Files and directories whose name starts with _ are loaded
;; but are no page.  api/ is listed in routes.el for reading only: the
;; server reads that directory itself (nextel-server.el).  index.html has
;; the two places that are filled in:
;;
;;   <!-- nextel:framework --> <!-- /nextel:framework -->  this directory, shared/
;;   <!-- nextel:pages -->     <!-- /nextel:pages -->      pages/ and routes.el

;;; Code:

(require 'cl-lib)
(require 'subr-x)

(defconst nextel-build--here (file-name-directory (or load-file-name buffer-file-name default-directory))
  "The directory of this file: the framework's Lisp.")

(load (expand-file-name "nextel-route.el" nextel-build--here) nil t)
(declare-function nextel-pattern-of-file "nextel-route")
(declare-function nextel-pattern< "nextel-route")

(defgroup nextel nil
  "Files as pages for elisp-react."
  :group 'tools)

(defvar nextel-mount-selector "#app"
  "Where routes.el mounts the application (`nextel-start').")

(defvar nextel-routes-file "routes.el"
  "The file, relative to the project, that `nextel-write-routes' writes.")

(defun nextel--framework-directory (root)
  "This file's directory relative to ROOT (\"vendor/elisp-next/lisp/\"),
from where the page loads the framework: a copy of it in the project."
  (let ((relative (file-relative-name nextel-build--here root)))
    (when (string-prefix-p ".." relative)
      (error "nextel: load the copy of nextel-build.el that is in the project (vendor/elisp-next/lisp/), not %s"
             nextel-build--here))
    (file-name-as-directory relative)))

(defun nextel-project-root (&optional file)
  "The project of FILE (or of `default-directory'): the directory above it
that has index.html and pages/, or nil."
  (when-let* ((directory (locate-dominating-file
                          (or file default-directory)
                          (lambda (directory)
                            (and (file-exists-p (expand-file-name "index.html" directory))
                                 (file-directory-p (expand-file-name "pages" directory)))))))
    (file-name-as-directory (expand-file-name directory))))

(defun nextel--lisp-files (directory)
  "The .el files under DIRECTORY, relative to it with /, sorted, without
hidden files and directories."
  (when (file-directory-p directory)
    (sort (cl-remove-if (lambda (file) (cl-some (lambda (part) (string-prefix-p "." part)) (split-string file "/" t)))
                        (mapcar (lambda (file) (file-relative-name file directory))
                                (directory-files-recursively directory "\\.el\\'")))
          #'string<)))

(defun nextel--private-p (file)
  (cl-some (lambda (part) (string-prefix-p "_" part)) (split-string file "/" t)))

(defun nextel--named (pages file form)
  "The NAME of (FORM NAME ...) in the file FILE of PAGES."
  (with-temp-buffer
    (insert-file-contents (expand-file-name file pages))
    (goto-char (point-min))
    (if (re-search-forward (concat "(" (regexp-quote form) "[ \t\n]+\\([^ \t\n()]+\\)") nil t)
        (match-string 1)
      (error "pages/%s has no (%s NAME ...)" file form))))

(defun nextel-read-project (root)
  "What pages/, api/ and shared/ of ROOT say: a plist (:routes ((PATTERN
PAGE FILE) ...) :layout :not-found :api ((PATTERN FILE) ...) :shared FILES
:page-scripts FILES)."
  (let* ((pages (expand-file-name "pages/" root))
         (routes nil) (layout nil) (not-found nil) (helpers nil) (page-files nil))
    (dolist (file (nextel--lisp-files pages))
      (cond ((equal file "_layout.el")
             (setq layout (nextel--named pages file "nextel-layout"))
             (push file helpers))
            ((equal file "404.el")
             (setq not-found (nextel--named pages file "nextel-page"))
             (push file page-files))
            ((nextel--private-p file) (setq helpers (append helpers (list file))))
            (t (let* ((pattern (nextel-pattern-of-file file))
                      (clash (assoc pattern routes)))
                 (when clash
                   (error "pages/%s and pages/%s are both %s" (nth 2 clash) file pattern))
                 (push (list pattern (nextel--named pages file "nextel-page") file) routes)
                 (push file page-files)))))
    (list :routes (sort routes (lambda (a b) (nextel-pattern< (car a) (car b))))
          :layout layout :not-found not-found
          :api (sort (mapcar (lambda (file) (list (nextel-pattern-of-file (concat "api/" file)) (concat "api/" file)))
                             (cl-remove-if #'nextel--private-p (nextel--lisp-files (expand-file-name "api/" root))))
                     (lambda (a b) (nextel-pattern< (car a) (car b))))
          :shared (mapcar (lambda (file) (concat "shared/" file)) (nextel--lisp-files (expand-file-name "shared/" root)))
          :page-scripts (mapcar (lambda (file) (concat "pages/" file))
                                (append helpers (sort page-files #'string<))))))

(defun nextel-routes-text (project)
  "The text of `nextel-routes-file' for PROJECT (`nextel-read-project')."
  (let* ((routes (plist-get project :routes))
         (width (apply #'max 0 (mapcar (lambda (route) (+ 2 (length (car route)))) routes))))
    (concat
     ";;; routes.el --- which page is which address  -*- lexical-binding: t; -*-\n\n"
     ";; Written by nextel-build.el (elisp-next) from pages/: do not edit,\n"
     ";; write it again (M-x nextel-write-routes, or bin/nextel-routes).\n"
     ";;\n"
     ";; The server's routes, from api/ (nextel-server.el reads that directory itself):\n"
     (if (plist-get project :api)
         (mapconcat (lambda (route) (format (format ";;   %%-%ds  %%s" width) (car route) (cadr route)))
                    (plist-get project :api) "\n")
       ";;   (none)")
     "\n\n(nextel-define-routes\n '("
     (mapconcat (lambda (route) (format "(%s . %s)" (prin1-to-string (car route)) (cadr route))) routes "\n   ")
     ")"
     (if (plist-get project :layout) (format "\n :layout '%s" (plist-get project :layout)) "")
     (if (plist-get project :not-found) (format "\n :not-found '%s" (plist-get project :not-found)) "")
     ")\n\n"
     (format "(nextel-start %s)\n\n" (prin1-to-string nextel-mount-selector))
     ";;; routes.el ends here\n")))

(defun nextel--fill (html name sources)
  "HTML with the <script> tags of SOURCES between its two NAME markers."
  (with-temp-buffer
    (insert html)
    (goto-char (point-min))
    (unless (re-search-forward (format "<!-- nextel:%s -->" name) nil t)
      (error "index.html has no <!-- nextel:%s --> ... <!-- /nextel:%s -->" name name))
    (let ((start (point)))
      (unless (re-search-forward (format "^[ \t]*<!-- /nextel:%s -->" name) nil t)
        (error "index.html has no <!-- /nextel:%s -->" name))
      (delete-region start (match-beginning 0))
      (goto-char start)
      (insert "\n" (mapconcat (lambda (src) (format "    <script type=\"text/emacs-lisp\" src=\"%s\"></script>" src))
                              sources "\n")
              "\n"))
    (buffer-string)))

(defun nextel-index-text (html project root)
  "index.html (its text HTML) of ROOT with the places for PROJECT filled in."
  (let ((framework (nextel--framework-directory root)))
    (nextel--fill (nextel--fill html "framework"
                                (append (mapcar (lambda (name) (concat framework name))
                                                '("nextel-schema.el" "nextel-route.el" "nextel.el"))
                                        (plist-get project :shared)))
                  "pages" (append (plist-get project :page-scripts) (list nextel-routes-file)))))

(defun nextel--file-text (file)
  (and (file-exists-p file)
       (with-temp-buffer
         (let ((coding-system-for-read 'utf-8)) (insert-file-contents file))
         (buffer-string))))

(defun nextel--outputs (root)
  "((FILE . TEXT) ...): what the routes of ROOT are to be."
  (let ((project (nextel-read-project root))
        (index (expand-file-name "index.html" root)))
    (list (cons (expand-file-name nextel-routes-file root) (nextel-routes-text project))
          (cons index (nextel-index-text (nextel--file-text index) project root)))))

(defun nextel--write (file text)
  "Make FILE's text TEXT: through its buffer when one visits it (so that
the buffer and the file stay one), else directly."
  (let ((buffer (find-buffer-visiting file)))
    (if (not buffer)
        (let ((coding-system-for-write 'utf-8-unix))
          (write-region text nil file nil 'silent))
      (with-current-buffer buffer
        (when (buffer-modified-p)
          (error "%s has changes that are not saved: save it, then write the routes" (file-name-nondirectory file)))
        (save-restriction
          (widen)
          (erase-buffer)
          (insert text))
        (save-buffer)))))

(defun nextel-write-routes (&optional root)
  "Write `nextel-routes-file' and the <script> tags of index.html from pages/.
ROOT is the project, by default the one of the current buffer's file.
Returns the files that changed."
  (interactive)
  (let* ((root (or root (nextel-project-root (or buffer-file-name default-directory))
                   (user-error "Not in a project with index.html and pages/")))
         (project (nextel-read-project root))
         (written nil))
    (pcase-dolist (`(,file . ,text) (nextel--outputs root))
      (unless (equal (nextel--file-text file) text)
        (nextel--write file text)
        (push (file-relative-name file root) written)))
    (setq written (nreverse written))
    (message "nextel: %d pages, %d API routes%s"
             (length (plist-get project :routes)) (length (plist-get project :api))
             (if written (concat ": wrote " (string-join written ", ")) ", nothing changed"))
    written))

(defun nextel-check-routes ()
  "In batch: exit 1 if the routes of the project here are not up to date."
  (let* ((root (or (nextel-project-root default-directory) (error "Not in a project with index.html and pages/")))
         (stale (cl-remove-if (lambda (output) (equal (nextel--file-text (car output)) (cdr output)))
                              (nextel--outputs root))))
    (if (null stale)
        (message "nextel: the routes are up to date")
      (message "nextel: not up to date: %s; write them (M-x nextel-write-routes, bin/nextel-routes)"
               (mapconcat (lambda (output) (file-relative-name (car output) root)) stale ", ")))
    (when noninteractive (kill-emacs (if stale 1 0)))
    (null stale)))

(defun nextel--stamp (root)
  "What pages/, api/ and shared/ of ROOT are now: their files and times."
  (mapcan (lambda (name)
            (let ((directory (expand-file-name name root)))
              (mapcar (lambda (file)
                        (cons file (file-attribute-modification-time
                                    (file-attributes (expand-file-name file directory)))))
                      (nextel--lisp-files directory))))
          '("pages/" "api/" "shared/")))

(defun nextel-watch-routes ()
  "In batch: write the routes whenever pages/, api/ or shared/ change.
For an editor other than Emacs; in Emacs, `nextel-routes-mode'."
  (let ((root (or (nextel-project-root default-directory) (error "Not in a project with index.html and pages/")))
        (seen nil))
    (message "nextel: watching pages/, api/ and shared/ of %s" root)
    (while t
      (let ((now (nextel--stamp root)))
        (unless (equal now seen)
          (setq seen now)
          (condition-case failure (nextel-write-routes root)
            (error (message "nextel: %s" (error-message-string failure))))))
      (sleep-for 0.5))))

(defun nextel--after-save ()
  "After a save of a file of pages/, api/ or shared/: write the routes."
  (when-let* ((file buffer-file-name)
              (root (nextel-project-root file)))
    (when (string-match-p "\\`\\(?:pages\\|api\\|shared\\)/" (file-relative-name file root))
      (condition-case failure (nextel-write-routes root)
        (error (message "nextel: %s" (error-message-string failure)))))))

(define-minor-mode nextel-routes-mode
  "Write the routes (`nextel-write-routes') after every save of a file of
pages/, api/ or shared/.  A page that is added is then there as soon as it
is saved; one that is deleted or renamed outside a save needs
\\[nextel-write-routes]."
  :global t
  :group 'nextel
  :lighter " nextel"
  (if nextel-routes-mode
      (add-hook 'after-save-hook #'nextel--after-save)
    (remove-hook 'after-save-hook #'nextel--after-save)))

(provide 'nextel-build)
;;; nextel-build.el ends here
