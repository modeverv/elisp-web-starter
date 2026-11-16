;;; health.el --- GET /api/health  -*- lexical-binding: t; -*-

;; The server is up and reaches its database: for a monitor, a smoke test
;; after a deployment (curl .../api/health), and the about page.

(nextel-handle "GET"
  :returns 'starter-health
  :handler (lambda (_request)
             (make-starter-health :status "ok"
                                  :emacs emacs-version
                                  :database (symbol-name (app-server-sql-backend))
                                  :notes (starter-count-notes)
                                  :versions (starter-versions))))

;;; health.el ends here
