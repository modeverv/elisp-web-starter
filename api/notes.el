;;; notes.el --- GET and POST /api/notes  -*- lexical-binding: t; -*-

;; GET /api/notes?q=TEXT   the notes, the last changed first; with q, those
;;                         whose title or text has TEXT in it
;; POST /api/notes         a new note from a starter-draft; the note
;;
;; The body is checked against :accepts before the handler runs (400 with
;; the field that is wrong), the answer against :returns (500, logged).

(nextel-handle "GET"
  :returns '(list-of starter-note)
  :handler (lambda (_request) (starter-notes (app-server-parameter "q"))))

(nextel-handle "POST"
  :accepts 'starter-draft
  :returns 'starter-note
  :handler (lambda (request) (starter-add-note (plist-get request :body))))

;;; notes.el ends here
