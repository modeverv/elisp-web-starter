;;; about.el --- /about: what runs this application  -*- lexical-binding: t; -*-

(nextel-page AboutPage
  :load (lambda (_route) (nextel-request "GET" "/api/health" :returns 'starter-health))
  :head (lambda (_route _health) (list :title "About"))
  :render
  (lambda (self)
    (let ((health (nextel-data self)))
      (jsx (article (:class "about")
             (h1 "About")
             (p "A starter for web applications written in Emacs Lisp. The page and the server
are both GNU Emacs: one runs in this tab as WebAssembly, the other on the server.")
             (dl (:class "facts")
               (dt "The page") (dd (:class "page-emacs") "GNU Emacs " emacs-version)
               (dt "The server") (dd (:class "server-emacs") "GNU Emacs " (starter-health-emacs health))
               (dt "Database") (dd (:class "database") (starter-health-database health))
               (dt "Notes") (dd (:class "count") (number-to-string (starter-health-notes health))))
             (h2 "Versions")
             (p "As the project's VERSIONS file names them:")
             (ul (:class "versions")
               (mapcar (lambda (line) (jsx (li (:key line) (code line))))
                       (starter-health-versions health))))))))

;;; about.el ends here
