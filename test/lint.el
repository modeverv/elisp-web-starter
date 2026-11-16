;;; lint.el --- every .el file of the project compiles without a warning  -*- lexical-binding: t; -*-

;; test/run.sh runs it once for each side, each in an Emacs of its own, so
;; that a function of one side is not taken for one of the other:
;;
;;   emacs --batch -Q -l test/lint.el --eval '(starter-lint "page")'
;;   emacs --batch -Q -l test/lint.el --eval '(starter-lint "server")'
;;
;; The page: react.el, then the scripts of index.html in their order, as the
;; page loads them; then the project's own scripts (not vendor/) are
;; compiled.  The server: app-server.el and server.el, which loads shared/
;; and api/, as serve-project.el does; then server.el, shared/ and api/ are
;; compiled.  A warning fails: an unknown function or variable, a call with
;; the wrong number of arguments, a file without lexical-binding.

(require 'bytecomp)
(require 'cl-lib)
(require 'seq)

(defconst starter-lint-root
  (file-name-directory (directory-file-name (file-name-directory (or load-file-name buffer-file-name))))
  "The project.")

(add-to-list 'load-path (expand-file-name "vendor/elisp-react/lisp" starter-lint-root))
(add-to-list 'load-path (expand-file-name "vendor/elisp-next/lisp" starter-lint-root))

(defun starter-lint-scripts ()
  "The src of each <script type=\"text/emacs-lisp\"> of index.html, in order."
  (with-temp-buffer
    (insert-file-contents (expand-file-name "index.html" starter-lint-root))
    (let (scripts)
      (while (re-search-forward "<script type=\"text/emacs-lisp\" src=\"\\([^\"]+\\)\"" nil t)
        (push (match-string 1) scripts))
      (nreverse scripts))))

(defun starter-lint-files (directory)
  "The .el files under DIRECTORY of the project, relative to it, sorted."
  (let ((root (expand-file-name directory starter-lint-root)))
    (and (file-directory-p root)
         (sort (mapcar (lambda (file) (file-relative-name file starter-lint-root))
                       (seq-remove (lambda (file) (string-match-p "/\\.[^/]*\\'" file))
                                   (directory-files-recursively root "\\.el\\'")))
               #'string<))))

(defun starter-lint-compile (side files)
  "Compile FILES of the project, warnings as errors; end Emacs with 1 if one fails."
  (let* ((output (make-temp-file "starter-lint-" t))
         (byte-compile-error-on-warn t)
         (byte-compile-dest-file-function
          (lambda (file) (expand-file-name (concat (md5 file) ".elc") output)))
         (failed (cl-remove-if (lambda (file) (byte-compile-file (expand-file-name file starter-lint-root)))
                               files)))
    (delete-directory output t)
    (if failed
        (progn (message "lint (%s): these do not compile without a warning: %s"
                        side (mapconcat #'identity failed ", "))
               (kill-emacs 1))
      (message "lint (%s): %d files compile without a warning" side (length files)))))

(defun starter-lint (side)
  "Compile the project's files of SIDE, \"page\" or \"server\"."
  (pcase side
    ("page"
     (require 'react-testing)          ; a page without a browser: routes.el mounts the application
     (react-testing-reset)
     (let ((scripts (starter-lint-scripts)))
       (dolist (script scripts)
         (load (expand-file-name script starter-lint-root) nil t))
       (starter-lint-compile side (seq-remove (lambda (file) (string-prefix-p "vendor/" file)) scripts))))
    ("server"
     (load (expand-file-name "server/app-server.el" starter-lint-root) nil t)
     (defvar app-server-data-directory)
     (setq app-server-data-directory (file-name-as-directory (make-temp-file "starter-lint-data-" t)))
     (app-server-use-project starter-lint-root)
     (load (expand-file-name "server.el" starter-lint-root) nil t)
     (starter-lint-compile side (append '("server.el") (starter-lint-files "shared") (starter-lint-files "api"))))
    (_ (error "starter-lint: SIDE is \"page\" or \"server\", not %S" side))))

;;; lint.el ends here
