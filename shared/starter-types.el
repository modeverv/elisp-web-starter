;;; starter-types.el --- what the page and the server send each other  -*- lexical-binding: t; -*-

;; Both sides load this file: the page (index.html lists it, before the
;; pages) and the server (`nextel-server-load', before api/).  So it may
;; use Emacs and nextel-schema.el only: no react.el (the server has none)
;; and no app-server.el (the page has none).
;;
;; `nextel-defschema' NAME defines make-NAME (checked), NAME-p and NAME-FIELD
;; for each field: those names are taken.  Helpers of your own get names
;; outside them (`starter-check-draft', not `starter-draft-check').

(require 'nextel-schema)
(require 'subr-x)

(nextel-defschema starter-note
  "A note, as the server keeps it and sends it."
  (id string :required t)
  (title string :required t)
  (body string)
  (done boolean)
  (created integer :required t)   ; seconds since 1970 (UTC)
  (updated integer :required t))

(nextel-defschema starter-draft
  "What the page sends to make a note (POST /api/notes) or to change one
\(PUT /api/notes/ID, which replaces all three fields)."
  (title string :required t)
  (body string)
  (done boolean))

(nextel-defschema starter-health
  "GET /api/health: the server is up, and what it runs on."
  (status (member "ok") :required t)
  (emacs string :required t)
  (database (member "sqlite" "mysql") :required t)
  (notes integer :required t)
  (versions (list-of string)))

(defconst starter-title-limit 200 "The longest title, in characters.")
(defconst starter-body-limit 20000 "The longest text of a note, in characters.")

(defun starter-check-draft (draft)
  "What is wrong with DRAFT (a `starter-draft') beyond its type, or nil.
The page asks before it sends; the server asks again, since anyone can
send it anything."
  (let ((title (string-trim (or (starter-draft-title draft) ""))))
    (cond ((string-empty-p title) "A note needs a title")
          ((> (length title) starter-title-limit)
           (format "A title has at most %d characters" starter-title-limit))
          ((> (length (or (starter-draft-body draft) "")) starter-body-limit)
           (format "A note has at most %d characters" starter-body-limit)))))

;;; starter-types.el ends here
