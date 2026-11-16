;;; _notes.el --- the notes, kept in SQL  -*- lexical-binding: t; -*-

;; A helper of api/ (its name starts with _): loaded before the routes,
;; never a route itself.  What more than one route needs is here: on a
;; shared host each request is an Emacs of its own that loads only the
;; route file that answers it (elisp-next's pitfall 27).
;;
;; `app-server-sql-select' and the rest go to SQLite (.data/app.db under
;; run.sh; the browser's storage in elisp-studio) or to MySQL (a shared
;; host, APP_MYSQL): the same statements, only the tables are written twice.
;; Every value goes in as a parameter (?), never into the SQL text.

(require 'seq)
(require 'subr-x)

(defconst starter-tables
  '((sqlite
     "CREATE TABLE IF NOT EXISTS starter_notes (
        id INTEGER PRIMARY KEY AUTOINCREMENT, title TEXT NOT NULL, body TEXT NOT NULL,
        done INTEGER NOT NULL DEFAULT 0, created INTEGER NOT NULL, updated INTEGER NOT NULL)")
    (mysql
     "CREATE TABLE IF NOT EXISTS starter_notes (
        id INT AUTO_INCREMENT PRIMARY KEY, title VARCHAR(200) NOT NULL, body MEDIUMTEXT NOT NULL,
        done TINYINT NOT NULL DEFAULT 0, created BIGINT NOT NULL, updated BIGINT NOT NULL)
        ENGINE=InnoDB DEFAULT CHARSET=utf8mb4"))
  "The tables, for each kind of database.")

(defun starter-sql (function &rest arguments)
  "FUNCTION (`app-server-sql-select' and the rest) on ARGUMENTS.
The tables are made the first time the database says one is missing,
so a new database needs nothing done to it."
  (condition-case err
      (apply function arguments)
    (error
     (unless (string-match-p "no such table\\|1146" (format "%s" (cdr err)))
       (signal (car err) (cdr err)))
     (dolist (sql (cdr (assq (app-server-sql-backend) starter-tables)))
       (app-server-sql-execute sql))
     (apply function arguments))))

(defconst starter-columns "id, title, body, done, created, updated"
  "The columns of a note, in the order of `starter-row-note'.")

(defun starter-row-note (row)
  "The `starter-note' of ROW, the values of `starter-columns'."
  (pcase-let ((`(,id ,title ,body ,done ,created ,updated) row))
    (make-starter-note :id (format "%s" id) :title title :body body
                       :done (equal done 1) :created created :updated updated)))

(defun starter-now ()
  "Seconds since 1970."
  (truncate (float-time)))

(defun starter-like (text)
  "A LIKE pattern that finds TEXT anywhere: its % and _ match only themselves."
  (concat "%" (replace-regexp-in-string "[!%_]" "!\\&" text) "%"))

(defun starter-notes (&optional search)
  "Every note, the last changed first; only those with SEARCH in them, if given."
  (mapcar #'starter-row-note
          (if (and search (not (string-empty-p (string-trim search))))
              (let ((pattern (starter-like (string-trim search))))
                (starter-sql #'app-server-sql-select
                             (format "SELECT %s FROM starter_notes WHERE title LIKE ? ESCAPE '!' OR body LIKE ? ESCAPE '!'
                                      ORDER BY updated DESC, id DESC" starter-columns)
                             (list pattern pattern)))
            (starter-sql #'app-server-sql-select
                         (format "SELECT %s FROM starter_notes ORDER BY updated DESC, id DESC" starter-columns)))))

(defun starter-count-notes ()
  "How many notes there are."
  (caar (starter-sql #'app-server-sql-select "SELECT COUNT(*) FROM starter_notes")))

(defun starter-find-note (id)
  "The note whose id is ID (a string), or nil."
  (and (stringp id)
       (string-match-p "\\`[0-9]\\{1,9\\}\\'" id)
       (let ((row (car (starter-sql #'app-server-sql-select
                                    (format "SELECT %s FROM starter_notes WHERE id = ?" starter-columns)
                                    (list (string-to-number id))))))
         (and row (starter-row-note row)))))

(defun starter-valid-draft (draft)
  "DRAFT with its title trimmed, or a refusal (400) of what is wrong with it.
The body has been checked against `starter-draft' already (:accepts)."
  (let ((problem (starter-check-draft draft)))
    (when problem (app-server-refuse problem 400))
    (list :title (string-trim (starter-draft-title draft))
          :body (or (starter-draft-body draft) "")
          :done (and (starter-draft-done draft) t))))

(defun starter-add-note (draft)
  "Keep a new note made of DRAFT; the note."
  (let* ((draft (starter-valid-draft draft))
         (now (starter-now))
         (id (starter-sql #'app-server-sql-insert
                          "INSERT INTO starter_notes (title, body, done, created, updated) VALUES (?, ?, ?, ?, ?)"
                          (list (plist-get draft :title) (plist-get draft :body)
                                (if (plist-get draft :done) 1 0) now now))))
    (starter-find-note (format "%s" id))))

(defun starter-change-note (id draft)
  "Replace the title, text and done of the note ID with DRAFT; the note, or nil."
  (when (starter-find-note id)
    (let ((draft (starter-valid-draft draft)))
      (starter-sql #'app-server-sql-execute
                   "UPDATE starter_notes SET title = ?, body = ?, done = ?, updated = ? WHERE id = ?"
                   (list (plist-get draft :title) (plist-get draft :body)
                         (if (plist-get draft :done) 1 0) (starter-now) (string-to-number id)))
      (starter-find-note id))))

(defun starter-delete-note (id)
  "Delete the note ID; the note as it was, or nil."
  (let ((note (starter-find-note id)))
    (when note
      (starter-sql #'app-server-sql-execute "DELETE FROM starter_notes WHERE id = ?" (list (string-to-number id))))
    note))

(defun starter-request-id (request)
  "The [id] of the route of REQUEST."
  (plist-get (plist-get request :params) :id))

(defun starter-no-note ()
  "Refuse: there is no such note (404)."
  (app-server-refuse "No such note" 404))

(defun starter-versions ()
  "The lines NAME=VERSION of the project's VERSIONS file, or nil without one."
  (let ((file (expand-file-name "VERSIONS" app-server-project-directory)))
    (and (file-readable-p file)
         (with-temp-buffer
           (insert-file-contents file)
           (seq-filter (lambda (line) (string-match-p "\\`[A-Z_]+=" line))
                       (split-string (buffer-string) "\n" t))))))

;;; _notes.el ends here
