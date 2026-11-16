;;; server.el --- the server side: the files of api/  -*- lexical-binding: t; -*-

;; Each file of api/ answers the address that its path is (elisp-next):
;;
;;   api/notes.el       GET, POST /api/notes
;;   api/notes/[id].el  GET, PUT, DELETE /api/notes/ID
;;   api/health.el      GET /api/health
;;   api/_notes.el      a helper (_): the notes table, for all of them
;;
;; with the types of shared/starter-types.el, which the page checks too.
;; run.sh (a native Emacs), elisp-studio and a CGI host run this file, on
;; elisp-studio's app-server.el (server/); `app-server-project-directory'
;; is the project.  Keep it to these three lines: a route is a file of api/.

(declare-function nextel-server-load "nextel-server")   ; defined by the file loaded here
(load (expand-file-name "vendor/elisp-next/lisp/nextel-server.el" app-server-project-directory) nil t)
(nextel-server-load)

;;; server.el ends here
