;;; routes.el --- which page is which address  -*- lexical-binding: t; -*-

;; Written by nextel-build.el (elisp-next) from pages/: do not edit,
;; write it again (M-x nextel-write-routes, or bin/nextel-routes).
;;
;; The server's routes, from api/ (nextel-server.el reads that directory itself):
;;   /api/notes/[id]  api/notes/[id].el
;;   /api/health    api/health.el
;;   /api/notes     api/notes.el

(nextel-define-routes
 '(("/notes/[id]" . NotePage)
   ("/about" . AboutPage)
   ("/" . HomePage))
 :layout 'Layout
 :not-found 'NotFoundPage)

(nextel-start "#app")

;;; routes.el ends here
