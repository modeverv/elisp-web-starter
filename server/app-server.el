;;; app-server.el --- what a project's server.el runs on  -*- lexical-binding: t; -*-

;; Copyright (c) 2026 modeverv
;; SPDX-License-Identifier: MIT

;; A project may have a server side: a file server.el that defines
;;
;;   (defun app-server-handle (method path body) ...)
;;
;; METHOD is "GET", "POST", ...; PATH is the request's path, "/api/...",
;; without its query (`app-server-parameter' gives the values of
;; ?name=value); BODY is the text of the request (`app-server-data' reads it
;; as Lisp data).  The function returns Lisp
;; data, which is printed as the response (the page reads it back with
;; `read').  An error it signals becomes a 400 response with the error's
;; message, the error `file-missing' a 404.
;;
;; The same server.el runs in two places:
;;
;;   in the studio   in a third Emacs in the browser tab; the application's
;;                   requests to /api/... are handed to it directly
;;   for real        in a native Emacs that is a web server
;;                   (tools/serve-project.el)
;;
;; A handler that has to wait for something (another server, a moment to
;; pass) need not make everyone else wait.  It returns `app-server-defer':
;;
;;   ('("GET" "/api/rates")
;;    (app-server-defer
;;     (lambda (respond _fail)
;;       (app-server-fetch "https://example.com/rates.json"
;;                         :then (lambda (response)
;;                                 (funcall respond (plist-get response :text)))))))
;;
;; The request stays open, the server goes on with other requests, and the
;; answer is sent when RESPOND is called.  There are three things to wait
;; for: `app-server-fetch' (another server), `app-server-after' (a moment)
;; and, under a native Emacs only, `app-server-run' (a program).
;;
;; About the request and the answer, beyond the three arguments:
;;
;;   `app-server-data'                            the body, read as data
;;   `app-server-parameter'                       ?name=value
;;   `app-server-refuse'                          answer with an error status
;;   `app-server-header', `app-server-cookie'     what came with the request
;;   `app-server-set-header', `app-server-set-cookie', `app-server-delete-cookie'
;;   `app-server-token'                           a random name for a session
;;   `app-server-password-hash-later', `app-server-password-check-later'
;;                                                see "Passwords" below
;;   `app-server-session-start', `app-server-session', `app-server-session-end',
;;   `app-server-attempts-check'                  see "Signing in" below
;;   `app-server-upload', `app-server-keep-upload', `app-server-file',
;;   `app-server-send-file'                       files (see "Files" below)
;;
;; This file is loaded before server.el in both.  It gives the server
;; places to keep data:
;;
;;   `app-server-read', `app-server-write'   Lisp values in files
;;   `app-server-database'                   an SQLite database, for
;;                                           `sqlite-execute' and `sqlite-select'
;;
;; SQLite is part of Emacs (29 and later, when Emacs was built with it; the
;; Emacs of wasmacs is).  Where the data has to be in MySQL (a shared host,
;; whose Emacs may also be older and without SQLite), `app-server-sql-select',
;; `app-server-sql-execute', `app-server-sql-insert' and
;; `app-server-sql-transaction' work on either: SQLite by default, MySQL
;; when `app-server-mysql' names its option file.  Sessions and attempts
;; follow them.
;;
;; The server side runs on GNU Emacs 27.2 and later: what a shared host may
;; have (the CGI front end, tools/serve-cgi.el).

;;; Code:

(require 'cl-lib)
(require 'seq)
(require 'subr-x)
(require 'url-util)
(require 'json)

;; Emacs 27, which a shared host may have, has no `string-search' (28).
(unless (fboundp 'string-search)
  (defun string-search (needle haystack &optional start-pos)
    "Position of the string NEEDLE in HAYSTACK, or nil (as Emacs 28's)."
    (let ((case-fold-search nil))
      (string-match (regexp-quote needle) haystack start-pos))))

(defvar app-server-data-directory "/data/"
  "Where `app-server-write' keeps its files.")

(defvar app-server-project-directory default-directory
  "The project's directory, the one of server.el.
server.el loads the project's other files from here, as the page may:
  (load (expand-file-name \"shared.el\" app-server-project-directory) nil t)
It is on `load-path' too, after Emacs's own libraries, so `require'
finds a library of the project.  In the studio's tab the server's Emacs
has a copy of the project's text files here.")

(defun app-server-use-project (directory)
  "Take DIRECTORY as the project's directory (see `app-server-project-directory')."
  (setq app-server-project-directory (file-name-as-directory (expand-file-name directory)))
  (add-to-list 'load-path (directory-file-name app-server-project-directory) t))

(defun app-server-project-files ()
  "The files of the project that this Emacs has loaded, relative to it.
From `load-history'; a compiled file counts as its source."
  (let ((root (file-name-as-directory (expand-file-name app-server-project-directory)))
        (data (file-name-as-directory (expand-file-name app-server-data-directory)))
        (files nil))
    (dolist (entry load-history)
      (let ((file (car entry)))
        (when (and (stringp file) (string-prefix-p root file) (not (string-prefix-p data file)))
          (let ((name (substring file (length root))))
            (when (string-suffix-p ".elc" name) (setq name (substring name 0 -1)))
            (cl-pushnew name files :test #'equal)))))
    (nreverse files)))

(defun app-server--data-file (name)
  (unless (string-match-p "\\`[A-Za-z0-9_-]+\\'" name)
    (error "Not a name for server data: %S" name))
  (expand-file-name (concat name ".eld") app-server-data-directory))

(defvar app-server-mysql)           ; below, with the SQL

(defun app-server-read (name &optional default)
  "The Lisp value kept under NAME, or DEFAULT.
With `app-server-mysql' it is in the table app_server_data of that
database; otherwise in a file of the data directory."
  (let* ((file (app-server--data-file name))
         (row (and app-server-mysql
                   (car (app-server--own-sql 'mysql 'select "SELECT value FROM app_server_data WHERE name = ?"
                                             (list name))))))
    (cond (row (car (read-from-string (car row))))
          ;; Also what was kept in a file, before the data went to MySQL.
          ((file-readable-p file)
           (with-temp-buffer
             (insert-file-contents file)
             (read (current-buffer))))
          (t default))))

(defvar app-server-single-request nil
  "Non-nil when this Emacs answers one request and ends (a CGI:
tools/serve-cgi.el).  A library may then load at the start only what the
request needs: elisp-next loads the one file of api/ that answers.")

(defvar app-server-shared nil
  "Non-nil when several server processes share the data directory.
\(WORKERS=4 ./run.sh.)  What a handler keeps in a Lisp variable is then
known to one of them only: keep it with `app-server-write' or in the
database.")

(defun app-server-write (name value)
  "Keep the Lisp VALUE under NAME.  Returns VALUE.
It is replaced in one step: a reader sees the old value or the new one,
never half of one.  With `app-server-mysql', a row of the table
app_server_data; otherwise a file of the data directory."
  (if app-server-mysql
      (let ((print-length nil) (print-level nil))
        (app-server--data-file name)        ; the same names as for files
        (app-server--own-sql 'mysql 'execute
                             "INSERT INTO app_server_data (name, value, updated) VALUES (?, ?, ?) AS new
                              ON DUPLICATE KEY UPDATE value = new.value, updated = new.updated"
                             (list name (prin1-to-string value) (float-time)))
        value)
    (app-server--write-file name value)))

(defun app-server--write-file (name value)
  (let* ((file (app-server--data-file name))
         (print-length nil) (print-level nil)
         (coding-system-for-write 'utf-8-unix)
         (new (progn (make-directory (file-name-directory file) t)
                     (make-temp-file (concat file ".")))))
    (with-temp-file new
      (prin1 value (current-buffer))
      (insert "\n"))
    (set-file-modes new #o644)
    (rename-file new file t))
  value)

(defvar app-server--databases nil "Alist: name -> open SQLite database.")

(defun app-server-database (&optional name)
  "The SQLite database NAME (default \"app\") of this application.
It is a file in the server's data directory, opened on first use and
kept open.  Use it with `sqlite-execute' and `sqlite-select'; pass values
as parameters (\"... WHERE id = ?\" (list id)), never by building SQL
text from what a page sent."
  (unless (and (fboundp 'sqlite-available-p) (sqlite-available-p))
    (error "This Emacs has no SQLite support"))
  (let* ((name (or name "app"))
         (open (cdr (assoc name app-server--databases))))
    (if (and open (sqlitep open))
        open
      (unless (string-match-p "\\`[A-Za-z0-9_-]+\\'" name)
        (error "Not a name for a database: %S" name))
      (make-directory app-server-data-directory t)
      (let ((database (sqlite-open (expand-file-name (concat name ".db") app-server-data-directory))))
        ;; Another process may be writing (several workers, or the sqlite3
        ;; tool): wait for it instead of failing at once.
        (sqlite-pragma database "busy_timeout = 5000")
        ;; With several workers: readers and the one writer do not block
        ;; one another.
        (when app-server-shared (sqlite-pragma database "journal_mode = WAL"))
        (setf (alist-get name app-server--databases nil nil #'equal) database)
        database))))

(defvar app-server--tab nil "Non-nil in a server that lives in a browser tab.")

;;;; The request being answered

(cl-defstruct (app-server--request (:constructor app-server--request-create))
  parameters            ; the query: an alist (NAME VALUE)
  headers               ; alist (NAME . VALUE), names in lower case
  upload                ; (:file FILE :size BYTES :type STRING) when the body is a file
  response-headers)     ; list of (NAME . VALUE), newest first

(defvar app-server--request nil
  "The request being answered, also while functions of a deferred request run.")

(defun app-server--current-request ()
  (or app-server--request (error "No request is being answered")))

(defun app-server-parameter (name &optional default)
  "The value of ?NAME=... in the request being answered, or DEFAULT."
  (or (cadr (assoc name (app-server--request-parameters (app-server--current-request)))) default))

;; What a page sends is data, never a program.  Reading it with Emacs's
;; reader has a cost of its own, though: every name the reader has not seen
;; before becomes a symbol that Emacs keeps for good, so a visitor who
;; sends bodies full of new names fills the server's memory (measured: 80
;; requests, 500 MB).  `app-server-data' reads without that.

(defun app-server-data (text &optional default)
  "The Lisp data that TEXT, the body of a request, is the printed form of.
An empty TEXT is DEFAULT.  The data is strings, numbers, lists, vectors
and symbols that this Emacs already knows (the keywords and names
server.el itself uses, nil and t).  Anything else is refused: a name
nobody here uses, a structure that goes round in circles or is too
large, an object that is not plain data.  Nothing a visitor sends stays
in Emacs afterwards.  Use this, not `read', on what comes from outside."
  (if (string-match-p "\\`[ \t\r\n]*\\'" text)
      default
    (let* ((own (obarray-make 31))
           (value (let ((obarray own))
                    (condition-case nil
                        (car (read-from-string text))
                      (error (error "The request is not Lisp data")))))
           (left 200000))
      (cl-labels
          ((clean (data depth)
             (when (or (> depth 64) (< (setq left (1- left)) 0))
               (error "The request holds too much data"))
             (cond ((stringp data) (substring-no-properties data))
                   ((numberp data) data)
                   ((symbolp data)
                    (let ((name (symbol-name data)))
                      (cond ((equal name "nil") nil)
                            ((intern-soft name))      ; the symbol this Emacs knows by that name
                            (t (error "The request names something unknown: %s"
                                      (truncate-string-to-width name 40))))))
                   ((consp data)
                    ;; Along the list in a loop, so that a long list is not a deep one.
                    (let ((result nil))
                      (while (consp data)
                        (push (clean (car data) (1+ depth)) result)
                        (setq data (cdr data))
                        (when (< (setq left (1- left)) 0) (error "The request holds too much data")))
                      (let ((list (nreverse result)))
                        (when data (setcdr (last list) (clean data (1+ depth))))
                        list)))
                   ((and (vectorp data) (not (byte-code-function-p data)))
                    (apply #'vector (mapcar (lambda (element) (clean element (1+ depth))) data)))
                   (t (error "The request holds something that is not data")))))
        (clean value 0)))))

(defvar app-server-explain-errors t
  "Non-nil: the text of any error in a handler is the response.
That is for writing the application.  A server for others sets it to nil:
then only what server.el says on purpose (`error', `app-server-refuse')
reaches the visitor, and what went wrong inside (a file's path, a
database's message) goes to the log.")

(defun app-server--file-missing-text (err)
  "What the visitor is told about ERR, a `file-missing' condition.
server.el signals it on purpose for what is not there; Emacs signals it
for a file it did not find, with the file's whole name."
  (if (or app-server-explain-errors (not (member "No such file or directory" (cdr err))))
      (error-message-string err)
    (message "app-server: %s" (error-message-string err))
    "Not found"))

(defun app-server--error-text (err)
  "What the visitor is told about ERR, a condition a handler signalled."
  (cond ((or app-server-explain-errors (memq (car err) '(error user-error)))
         (error-message-string err))
        (t (message "app-server: %s" (error-message-string err))
           (if (eq (car err) 'file-missing) "Not found" "The request could not be answered"))))

(define-error 'app-server-refusal "The request is refused")

(defun app-server-refuse (message &optional status)
  "Refuse the request being answered: MESSAGE is the response.
STATUS is the HTTP status, 400 by default: 401 for a visitor who has to
sign in, 403 for one who may not, 404 for what is not there."
  (signal 'app-server-refusal (list message (or status 400))))

(defun app-server-header (name)
  "The value of the header NAME of the request being answered, or nil.
Behind a reverse proxy, \"x-forwarded-for\" and \"x-forwarded-proto\" are
what the proxy says about the visitor; they can be believed because the
server only listens to this machine."
  (cdr (assoc (downcase name) (app-server--request-headers (app-server--current-request)))))

(defun app-server-cookie (name)
  "The value of the cookie NAME that came with the request, or nil."
  (let ((header (app-server-header "cookie")) value)
    (dolist (pair (and header (split-string header ";" t "[ \t]+")))
      (let ((equals (string-search "=" pair)))
        (when (and equals (not value) (equal (substring pair 0 equals) name))
          (setq value (decode-coding-string (url-unhex-string (substring pair (1+ equals))) 'utf-8)))))
    value))

(defun app-server-set-header (name value)
  "Send the header NAME: VALUE with the answer to the request."
  (unless (string-match-p "\\`[A-Za-z0-9-]+\\'" name)
    (error "Not a header name: %S" name))
  (when (member (downcase name) '("content-length" "content-type" "connection" "transfer-encoding"))
    (error "The server sets %s itself" name))
  ;; A line break in a value would start a header of the sender's choosing.
  (when (string-match-p "[\0-\x1f\x7f]" value)
    (error "A header value cannot contain control characters"))
  (push (cons name value) (app-server--request-response-headers (app-server--current-request)))
  nil)

(defvar app-server-file-headers nil
  "Headers for the project's own files, as a native Emacs serves them.
A list of (REGEXP . HEADERS): a file whose path (\"/assets/logo.png\")
matches REGEXP gets HEADERS, a list of (NAME . VALUE), which replace the
server's headers of the same name; a later entry replaces an earlier one.
Files under /assets/ that never change, kept by browsers for a year:

  (setq app-server-file-headers
        \='((\"\\\\`/assets/\" (\"Cache-Control\" . \"public, max-age=31536000, immutable\"))))

In the studio the files come from the editor, without these headers.")

(defvar app-server-page-function nil
  "A function that fills the page in for a path, or nil.
A native Emacs calls it with the PATH of a request (\"/\", \"/watch/42\")
when it sends the project's index.html, and when a GET names no file.
It returns nil (the page as it is; for a path that is no file, 404) or a
plist, and the server sends index.html with that put in:

  :title TEXT              the page's <title>
  :meta ((NAME . TEXT)...) <meta> elements, which replace those of the
                           same name (og:... are written as property=)
  :html HTML               the content of the element with id \"app\",
                           as HTML: `react-render-to-string' makes it
  :status N                200 unless said

TEXT is escaped; HTML is not.  So a link to a route has its own title
and description for link previews and crawlers, and the page shows
content before its Emacs has started (it mounts over it).  react.el is
on the server's `load-path' when ./fetch-emacs.sh has put it in vendor/.
In the studio the page is index.html as it is.")

(defun app-server-set-cookie (name value &rest attributes)
  "Give the visitor's browser the cookie NAME with VALUE (a string).
ATTRIBUTES is a plist:

:max-age SECONDS   how long the browser keeps it; without, until it closes
:path STRING       \"/\" by default
:http-only FLAG    hidden from the page's scripts; t by default
:secure FLAG       only over HTTPS; by default, when the request came
                   over HTTPS (the proxy's X-Forwarded-Proto)
:same-site STRING  \"Lax\" (default), \"Strict\" or \"None\""
  (unless (string-match-p "\\`[A-Za-z0-9_-]+\\'" name)
    (error "Not a cookie name: %S" name))
  (let ((path (or (plist-get attributes :path) "/"))
        (same-site (or (plist-get attributes :same-site) "Lax"))
        (max-age (plist-get attributes :max-age)))
    (unless (member same-site '("Lax" "Strict" "None")) (error "Not a SameSite value: %S" same-site))
    (when (string-match-p "[;\0-\x1f\x7f]" path) (error "Not a cookie path: %S" path))
    (app-server-set-header
     "Set-Cookie"
     (concat name "=" (url-hexify-string value) "; Path=" path
             (and max-age (format "; Max-Age=%d" max-age))
             (and (if (plist-member attributes :http-only) (plist-get attributes :http-only) t) "; HttpOnly")
             (and (if (plist-member attributes :secure)
                      (plist-get attributes :secure)
                    (equal (app-server-header "x-forwarded-proto") "https"))
                  "; Secure")
             "; SameSite=" same-site))))

(defun app-server-delete-cookie (name)
  "Make the visitor's browser forget the cookie NAME."
  (app-server-set-cookie name "" :max-age 0))

;;;; Files: what visitors send, and sending files back

;; The body of a request is text for the handler, a megabyte at most.  A
;; file is something else: the server writes it to disk as it arrives and
;; the handler gets its name.  Which requests bring a file is for server.el
;; to say, before any of it is taken:
;;
;;   (defun app-server-upload-p (method path size)
;;     (and (equal path "/api/photos") (app-visitor) (< size (* 200 1024 1024))))
;;
;;   ('("POST" "/api/photos")
;;    (let ((name (concat (app-server-token 8) ".jpg")))
;;      (app-server-keep-upload name)
;;      name))
;;   ('("GET" "/api/photo")
;;    (app-server-send-file (app-server-file (app-server-parameter "name")) :type "image/jpeg"))
;;
;; The page sends the file itself as the body (fetch with a File), not a
;; form.

(defun app-server-upload ()
  "The file that came as the body of the request being answered, or nil.
A plist (:file FILE :size BYTES :type STRING): FILE is a temporary file,
gone when the request is answered unless the handler moved it away
\(`app-server-keep-upload').  A request brings a file when server.el
defines `app-server-upload-p' and that says so."
  (app-server--request-upload (app-server--current-request)))

(defun app-server-file (name)
  "The file NAME among the files this application keeps.
NAME is letters, digits, dots, hyphens and underscores, not starting with
a dot: a name that came from a visitor cannot point anywhere else."
  (unless (string-match-p "\\`[A-Za-z0-9_-][A-Za-z0-9._-]*\\'" name)
    (error "Not a name for a kept file: %S" name))
  (let ((directory (expand-file-name "files/" app-server-data-directory)))
    (make-directory directory t)
    (expand-file-name name directory)))

(defun app-server-files ()
  "The names of the files this application keeps, in alphabetical order."
  (let ((directory (expand-file-name "files/" app-server-data-directory)))
    (and (file-directory-p directory) (directory-files directory nil "\\`[^.]"))))

(defun app-server-keep-upload (name)
  "Keep the file that came with the request as `(app-server-file NAME)'.
Returns its size in bytes."
  (let ((upload (or (app-server-upload) (error "This request brought no file"))))
    (rename-file (plist-get upload :file) (app-server-file name) t)
    (plist-get upload :size)))

(cl-defstruct (app-server--file-answer (:constructor app-server--file-answer-create))
  file type name)

(defun app-server-send-file (file &rest options)
  "Answer the request with FILE: return this from `app-server-handle'.
\(Or pass it to the RESPOND of `app-server-defer'.)  OPTIONS is a plist:
:type STRING is its media type (\"application/octet-stream\" by default);
with :name STRING the browser saves it under that name instead of
showing it.  FILE is usually
`(app-server-file NAME)'; do not make a file name out of what a visitor
sent in any other way."
  (unless (file-regular-p file) (signal 'file-missing (list "No such file" (file-name-nondirectory file))))
  (app-server--file-answer-create :file file :type (plist-get options :type) :name (plist-get options :name)))

(defun app-server--answer-body (data)
  "What a host sends for DATA, the handler's answer: printed text, or
\(:file FILE :type TYPE :name NAME) for `app-server-send-file'."
  (if (app-server--file-answer-p data)
      (list :file (app-server--file-answer-file data)
            :type (or (app-server--file-answer-type data) "application/octet-stream")
            :name (app-server--file-answer-name data))
    (let ((print-length nil) (print-level nil))
      (prin1-to-string data))))

(defun app-server-upload-accept (method path size headers)
  "For the host: does the request that begins with HEADERS bring a file?
The value is t (take the body into a file), nil (it is an ordinary
request) or, when server.el refused it, the answer [STATUS TEXT HEADERS]."
  (when (fboundp 'app-server-upload-p)
    (let* ((question (string-search "?" path))
           (app-server--request
            (app-server--request-create
             :parameters (and question (url-parse-query-string (substring path (1+ question))))
             :headers headers))
           (answer (lambda (status message)
                     (vector status (prin1-to-string message)
                             (reverse (app-server--request-response-headers app-server--request))))))
      (condition-case err
          (and (funcall 'app-server-upload-p method (if question (substring path 0 question) path) size) t)
        (app-server-refusal (funcall answer (nth 2 err) (nth 1 err)))
        (file-missing (funcall answer 404 (app-server--file-missing-text err)))
        (error (funcall answer 400 (app-server--error-text err)))))))

(defun app-server-upload-file ()
  "For the host: a new temporary file to take an upload into."
  (let ((directory (expand-file-name "uploads/" app-server-data-directory)))
    (make-directory directory t)
    (expand-file-name (app-server-token 16) directory)))

(defun app-server-token (&optional bytes)
  "A random string nobody can guess: BYTES (default 32) random bytes in hex.
For the names of sessions and the like; `random' is not for that.  The
bytes are the system's (/dev/urandom); in the studio's browser tab that
is the browser's own generator."
  (let* ((bytes (or bytes 32))
         (data (with-temp-buffer
                 (set-buffer-multibyte nil)
                 (condition-case nil
                     ;; No start position: Emacs 30 refuses one for a device.
                     (insert-file-contents-literally "/dev/urandom" nil nil bytes)
                   ;; Emacs 29 does not read part of a device at all.
                   (error (erase-buffer)
                          (ignore-errors
                            (let ((coding-system-for-read 'binary))
                              (call-process "head" "/dev/urandom" t nil "-c" (number-to-string bytes))))))
                 (buffer-string))))
    (unless (= (length data) bytes) (error "This system gives no random bytes"))
    (mapconcat (lambda (byte) (format "%02x" byte)) data "")))

;;;; Passwords

;; A password is never kept: what is kept is a hash made to be slow, so
;; that whoever gets hold of the database cannot try a billion guesses a
;; second.
;;
;;   ('("POST" "/api/login")
;;    (let* ((sent (app-server-data body)) (name (car sent)) (password (cadr sent)))
;;      (app-server-defer
;;       (lambda (respond fail)
;;         (app-server-password-check-later
;;          password (app-stored-hash name)
;;          (lambda (right)
;;            (if (not right)
;;                (funcall fail "Wrong name or password" 401)
;;              (app-server-set-cookie "session" (app-new-session name))
;;              (funcall respond t))))))))
;;
;; server.el asks with `app-server-password-hash-later' and
;; `app-server-password-check-later'; where the arithmetic is done depends
;; on where the server runs, and server.el does not see the difference:
;;
;;   a native Emacs    another process: python3 (its hashlib is OpenSSL's C),
;;                     or, where there is no python3, a second Emacs running
;;                     the Lisp below
;;   the studio's tab  the page, with the browser's own Web Crypto
;;
;; The hash is PBKDF2 with HMAC-SHA-256 (RFC 8018), 600,000 rounds (OWASP's
;; number for it), which all three can compute, with the same result.
;; `app-server-password-algorithm' can be `scrypt' instead, which costs an
;; attacker memory as well as time; only python3 computes that, so it is
;; for a server that has one.  A hash says how it was made
;; ("pbkdf2-sha256$600000$SALT$HASH", "scrypt$ln=17,r=8,p=1$SALT$HASH"), so
;; hashes made before a change of these settings stay valid.

(defvar app-server-password-algorithm 'pbkdf2-sha256
  "How new password hashes are made: `pbkdf2-sha256' or `scrypt'.
`scrypt' needs a python3 whose hashlib has it, on the server; the
studio's browser tab cannot compute it.")

(defvar app-server-password-rounds 600000
  "How many rounds a new PBKDF2 hash gets.")

(defvar app-server-password-scrypt "ln=17,r=8,p=1"
  "The cost of a new scrypt hash: N = 2^ln (here 128 MB of memory), r, p.")

(defvar app-server-password-python "python3"
  "The Python that hashes passwords for a native server, or nil for none.
Without one, a second Emacs does it, some twenty times slower.")

(defvar app-server-password-jobs (max 1 (if (fboundp 'num-processors) (num-processors) 2))
  "How many passwords are hashed at the same time; more wait their turn.")

(defconst app-server--file (or load-file-name buffer-file-name)
  "This file, for the second Emacs that hashes passwords.")

(defun app-server--pbkdf2 (password salt rounds)
  "PBKDF2-HMAC-SHA-256 of PASSWORD and SALT, unibyte strings: 32 bytes in hex."
  (let* ((key (if (> (length password) 64) (secure-hash 'sha256 password nil nil t) password))
         (block (concat key (make-string (- 64 (length key)) 0)))
         (inner (apply #'unibyte-string (mapcar (lambda (byte) (logxor byte #x36)) block)))
         (outer (apply #'unibyte-string (mapcar (lambda (byte) (logxor byte #x5c)) block)))
         (u (secure-hash 'sha256
                         (concat outer (secure-hash 'sha256 (concat inner salt (unibyte-string 0 0 0 1))
                                                    nil nil t))
                         nil nil t))
         (total (vconcat u)))
    (dotimes (_ (1- rounds))
      (setq u (secure-hash 'sha256 (concat outer (secure-hash 'sha256 (concat inner u) nil nil t))
                           nil nil t))
      (dotimes (index 32) (aset total index (logxor (aref total index) (aref u index)))))
    (mapconcat (lambda (byte) (format "%02x" byte)) total "")))

;; Its loop runs millions of times: compiled, whatever loaded this file.
(defvar byte-compile-warnings)
(unless (byte-code-function-p (symbol-function 'app-server--pbkdf2))
  (ignore-errors
    (require 'bytecomp)
    (let ((byte-compile-warnings nil))
      (byte-compile 'app-server--pbkdf2))))

(defun app-server--password-parse (hash)
  "The parts of HASH, (ALGORITHM PARAMETERS SALT DIGEST), or nil if it is none.
A hash whose cost is beyond reason is none either: checking it would
keep the machine busy for whoever wrote it."
  (let* ((parts (and (stringp hash) (split-string hash "\\$")))
         (cost (nth 1 parts)))
    (and (= (length parts) 4)
         (string-match-p "\\`[0-9a-f]+\\'" (nth 2 parts))
         (string-match-p "\\`[0-9a-f]+\\'" (nth 3 parts))
         (pcase (nth 0 parts)
           ("pbkdf2-sha256" (and (string-match-p "\\`[0-9]\\{1,8\\}\\'" cost)
                                 (<= 1 (string-to-number cost) 10000000)))
           ("scrypt" (and (string-match "\\`ln=\\([0-9]\\{1,2\\}\\),r=\\([0-9]\\{1,2\\}\\),p=\\([0-9]\\{1,2\\}\\)\\'" cost)
                          (<= 1 (string-to-number (match-string 1 cost)) 20)
                          (<= 1 (string-to-number (match-string 2 cost)) 32)
                          (<= 1 (string-to-number (match-string 3 cost)) 16))))
         parts)))

(defvar app-server-password-min-length 8
  "The shortest password that is hashed.  A shorter one is refused: no
hash makes a short password hard to guess.")

(defun app-server--password-acceptable (password)
  "Refuse the request if PASSWORD is not one to make a hash of."
  (unless (and (stringp password) (>= (length password) app-server-password-min-length))
    (app-server-refuse (format "A password needs at least %d characters" app-server-password-min-length)))
  (when (> (length password) 1024)
    (app-server-refuse "A password has at most 1024 characters")))

(defun app-server-password-needs-rehash-p (hash)
  "Non-nil if HASH was made with other settings than hashes are made with now.
After `app-server-password-rounds' was raised or
`app-server-password-algorithm' changed, old hashes still check; when a
visitor has just signed in with one, the password is at hand to make a
new one with (`app-server-password-hash-later') and store that."
  (let ((parts (app-server--password-parse hash)))
    (not (and parts
              (equal (nth 0 parts) (symbol-name app-server-password-algorithm))
              (equal (nth 1 parts) (app-server--password-parameters))))))

(defun app-server--same-p (one other)
  "Non-nil if the strings ONE and OTHER are equal.
All of them is compared: how long this takes says nothing about where
the first difference is."
  (and (stringp one) (stringp other) (= (length one) (length other))
       (let ((difference 0))
         (dotimes (index (length one))
           (setq difference (logior difference (logxor (aref one index) (aref other index)))))
         (= difference 0))))

(defun app-server--password-parameters ()
  "The cost of a new hash, as its second part says it."
  (pcase app-server-password-algorithm
    ('pbkdf2-sha256 (number-to-string app-server-password-rounds))
    ('scrypt app-server-password-scrypt)
    (_ (error "Not a way to hash passwords: %S" app-server-password-algorithm))))

;; Here, in this Emacs: for a script.  A handler would hold up everyone.

(defun app-server-password-hash (password)
  "A hash of PASSWORD, to keep instead of it.
It reads \"pbkdf2-sha256$ROUNDS$SALT$HASH\".  Takes seconds, during which
this Emacs does nothing else; in a handler use
`app-server-password-hash-later'."
  (app-server--password-acceptable password)
  (let ((salt (app-server-token 16)))
    (format "pbkdf2-sha256$%d$%s$%s" app-server-password-rounds salt
            (app-server--pbkdf2 (encode-coding-string password 'utf-8) salt app-server-password-rounds))))

(defun app-server-password-check (password hash)
  "Non-nil if PASSWORD is the one HASH was made of.
Takes as long as making the hash did; in a handler use
`app-server-password-check-later'.  Only for PBKDF2 hashes: this Emacs
cannot compute scrypt."
  (let ((parts (app-server--password-parse hash)))
    (and parts
         (if (equal (car parts) "pbkdf2-sha256")
             (app-server--same-p
              (app-server--pbkdf2 (encode-coding-string password 'utf-8) (nth 2 parts)
                                  (string-to-number (nth 1 parts)))
              (nth 3 parts))
           (error "A %s hash is checked with `app-server-password-check-later'" (car parts))))))

;; Elsewhere, while this Emacs goes on: for a handler.

(defvar app-server-kdf-function #'app-server--kdf-process
  "Function of (ALGORITHM PARAMETERS PASSWORD SALT THEN) that hashes.
It returns at once; THEN is called with the 32 bytes in hex, or with nil
when this host cannot compute ALGORITHM.  The hosts differ in this:
another process under a native Emacs, the page in the studio's tab.")

(defun app-server-password-hash-later (password function)
  "Hash PASSWORD without holding up the server; FUNCTION gets the hash.
For use inside `app-server-defer'.  A password shorter than
`app-server-password-min-length' is refused."
  (app-server--password-acceptable password)
  (let ((algorithm (symbol-name app-server-password-algorithm))
        (parameters (app-server--password-parameters))
        (salt (app-server-token 16)))
    (funcall app-server-kdf-function algorithm parameters password salt
             (app-server--guard
              (lambda (digest)
                (unless digest (error "This server cannot make %s hashes" algorithm))
                (funcall function (format "%s$%s$%s$%s" algorithm parameters salt digest)))))
    nil))

(defun app-server-password-check-later (password hash function)
  "Check PASSWORD against HASH without holding up the server.
FUNCTION gets t or nil.  For use inside `app-server-defer'."
  (let ((parts (app-server--password-parse hash))
        (function (app-server--guard function)))
    (if (not (and parts (stringp password) (<= (length password) 1024)))
        ;; No such account, most likely.  The answer takes as long as a
        ;; real check, or its speed would tell which names exist.
        (funcall app-server-kdf-function "pbkdf2-sha256" (number-to-string app-server-password-rounds)
                 "no password" "00" (lambda (_digest) (funcall function nil)))
      (funcall app-server-kdf-function (nth 0 parts) (nth 1 parts) password (nth 2 parts)
               (app-server--guard
                (lambda (digest)
                  (unless digest (error "This server cannot check %s hashes" (nth 0 parts)))
                  (funcall function (app-server--same-p digest (nth 3 parts)))))))
    nil))

;; Under a native Emacs: another process.

(defvar app-server-run-function)

(defconst app-server--kdf-script "\
import sys, hashlib, base64
algorithm, cost, salt, password = sys.stdin.read().split('\\n')[:4]
password = base64.b64decode(password)
salt = salt.encode()
if algorithm == 'pbkdf2-sha256':
    digest = hashlib.pbkdf2_hmac('sha256', password, salt, int(cost))
elif algorithm == 'scrypt':
    cost = dict(part.split('=') for part in cost.split(','))
    n, r, p = 1 << int(cost['ln']), int(cost['r']), int(cost['p'])
    digest = hashlib.scrypt(password, salt=salt, n=n, r=r, p=p, maxmem=132 * n * r * p + 1048576, dklen=32)
else:
    sys.exit(3)
sys.stdout.write(digest.hex())
"
  "What python3 runs to hash: the request on standard input, hex out.
The password comes by the pipe, not on the command line, where other
users of the machine could read it.")

(defvar app-server--kdf-python 'unknown
  "(PROGRAM ALGORITHM...) for the Python that hashes, or nil for none.")

(defun app-server--kdf-python ()
  "Find out, once, whether there is a Python and what its hashlib can do."
  (when (eq app-server--kdf-python 'unknown)
    (setq app-server--kdf-python
          (let ((program (and app-server-password-python (executable-find app-server-password-python))))
            (and program
                 (with-temp-buffer
                   (and (eq 0 (ignore-errors
                                (call-process program nil t nil "-c" "\
import hashlib
hashlib.pbkdf2_hmac('sha256', b'x', b'y', 1)
print('pbkdf2-sha256')
try:
    hashlib.scrypt(b'x', salt=b'y', n=2, r=1, p=1, dklen=8)
    print('scrypt')
except Exception:
    pass
")))
                        (cons program (split-string (buffer-string)))))))))
  app-server--kdf-python)

(defun app-server-password-hasher ()
  "A line for the log: what hashes passwords on this server."
  (let ((python (app-server--kdf-python)))
    (if python
        (format "%s (%s)" (car python) (string-join (cdr python) ", "))
      "a second Emacs (pbkdf2-sha256)")))

(defvar app-server--kdf-running 0)
(defvar app-server--kdf-waiting nil "Hashing that waits its turn: (JOB . THEN), oldest first.")

(defun app-server--kdf-next ()
  "Start waiting jobs, as many as may run at the same time."
  (while (and app-server--kdf-waiting (< app-server--kdf-running app-server-password-jobs))
    (let* ((next (pop app-server--kdf-waiting))
           (then (cdr next))
           (finished nil)
           (finish (lambda (digest)
                     (unless finished
                       (setq finished t)
                       (cl-decf app-server--kdf-running)
                       (unwind-protect
                           (funcall then (and (stringp digest) (string-match-p "\\`[0-9a-f]\\{64\\}\\'" digest)
                                              digest))
                         (app-server--kdf-next))))))
      (cl-incf app-server--kdf-running)
      (condition-case err
          (funcall (car next) finish)
        (error (message "app-server: hashing: %s" (error-message-string err))
               (funcall finish nil))))))

(defun app-server--kdf-process (algorithm parameters password salt then)
  "`app-server-kdf-function' for a native Emacs: python3, or a second Emacs."
  (let* ((python (app-server--kdf-python))
         (secret (base64-encode-string (encode-coding-string password 'utf-8) t))
         (command (cond ((member algorithm (cdr python))
                         (list (car python) "-c" app-server--kdf-script))
                        ((equal algorithm "pbkdf2-sha256")
                         (list (expand-file-name invocation-name invocation-directory) "--batch" "-Q"
                               "-l" app-server--file "--eval" "(app-server--password-child)")))))
    (if (not command)
        (funcall then nil)
      (setq app-server--kdf-waiting
            (append app-server--kdf-waiting
                    (list (cons (lambda (finish)
                                  (funcall app-server-run-function command
                                           (concat algorithm "\n" parameters "\n" salt "\n" secret "\n")
                                           (lambda (result)
                                             (funcall finish (and (eq (plist-get result :status) 0)
                                                                  (plist-get result :output))))))
                                then))))
      (app-server--kdf-next))))

(defun app-server--password-child ()
  "In the second Emacs: hash what standard input asks for, print the hex."
  (let ((lines (split-string (with-temp-buffer (insert-file-contents "/dev/stdin") (buffer-string)) "\n")))
    (unless (equal (nth 0 lines) "pbkdf2-sha256") (kill-emacs 3))
    (princ (app-server--pbkdf2 (base64-decode-string (nth 3 lines)) (nth 2 lines)
                               (string-to-number (nth 1 lines))))))

;;;; Signing in: sessions, and a limit on guesses

;; What signing in needs besides the password check: something that says
;; "this visitor is Ada" on later requests, and a stop to guessing.
;;
;;   ('("POST" "/api/login")
;;    (let* ((sent (app-server-data body)) (name (car sent)) (password (cadr sent))
;;           (address (app-server-visitor-address)))
;;      (app-server-attempts-check name address)        ; 429 after five failures in ten minutes
;;      (app-server-defer
;;       (lambda (respond fail)
;;         (app-server-password-check-later
;;          password (app-stored-hash name)
;;          (lambda (right)
;;            (if (not right)
;;                (progn (app-server-attempts-failed name address)
;;                       (funcall fail "Wrong name or password" 401))
;;              (app-server-attempts-clear name)
;;              (app-server-session-start name)         ; a cookie, for thirty days
;;              (funcall respond t))))))))
;;   ('("GET" "/api/me") (or (app-server-session) (app-server-refuse "Sign in first" 401)))
;;   ('("POST" "/api/logout") (app-server-session-end) t)
;;
;; Both are kept in an SQLite database of their own (.data/server.db), so
;; several workers share them and a restart does not sign everyone out.
;; In an Emacs without SQLite they are kept in memory.

;;;; SQL on SQLite or MySQL

(define-error 'app-server-sql-error "SQL error")
(declare-function sqlite-transaction "sqlite.c")
(declare-function sqlite-commit "sqlite.c")
(declare-function sqlite-rollback "sqlite.c")

(defvar app-server-mysql nil
  "nil, or the MySQL option file of the application's database.
Then `app-server-sql-select' and the rest use MySQL, through the `mysql'
client, and so do sessions and attempts.  The file has the connection
settings and the password ([client] host, user, password; [mysql]
database).  Keep it outside the web root, mode 600: it is the one place
the password is.  From the environment: APP_MYSQL.")

(defvar app-server-mysql-program "mysql" "The MySQL client.")

(defvar app-server-mysql-timeout 20
  "Seconds one statement may take before its connection is closed.")

(defvar app-server-mysql-keep nil
  "Non-nil: keep one MySQL connection for the life of this Emacs.
For a process that answers one request (tools/serve-cgi.el); a server
that answers many at once opens one per statement or transaction.")

(defvar app-server--mysql-process nil
  "The connection of the transaction under way, or the kept one.")
(defvar app-server--mysql-count 0)

(defun app-server-sql-backend ()
  "`mysql' or `sqlite': where `app-server-sql-select' and the rest go."
  (if app-server-mysql 'mysql 'sqlite))

(defun app-server--sql-literal-end (sql i)
  "The index after the quoted text that starts at I in SQL."
  (let ((quote (aref sql i)) (n (length sql)) (j (1+ i)) end)
    (while (and (not end) (< j n))
      (let ((c (aref sql j)))
        (cond ((and (eq c ?\\) (not (eq quote ?`))) (setq j (+ j 2)))
              ((eq c quote) (if (and (< (1+ j) n) (eq (aref sql (1+ j)) quote))
                                (setq j (+ j 2))
                              (setq end (1+ j))))
              (t (setq j (1+ j))))))
    (or end n)))

(defun app-server--sql-mask (sql &optional nested)
  "SQL with its quoted text and comments made blanks, the same length.
With NESTED, also what is inside parentheses (they stay)."
  (let ((out (copy-sequence sql)) (n (length sql)) (i 0) (depth 0))
    (cl-flet ((blank (from to) (cl-loop for k from from below (min to n) do (aset out k ?\s))))
      (while (< i n)
        (let ((c (aref sql i)) (next (and (< (1+ i) n) (aref sql (1+ i)))))
          (cond ((memq c '(?' ?\" ?`))
                 (let ((end (app-server--sql-literal-end sql i)))
                   (blank i end) (setq i end)))
                ((or (eq c ?#) (and (eq c ?-) (eq next ?-)))
                 (let ((end (or (string-match "\n" sql i) n)))
                   (blank i end) (setq i end)))
                ((and (eq c ?/) (eq next ?*))
                 (let ((end (if (string-match "\\*/" sql (+ i 2)) (match-end 0) n)))
                   (blank i end) (setq i end)))
                ((and nested (eq c ?\())
                 (when (> depth 0) (aset out i ?\s))
                 (setq depth (1+ depth) i (1+ i)))
                ((and nested (eq c ?\)))
                 (setq depth (max 0 (1- depth)))
                 (when (> depth 0) (aset out i ?\s))
                 (setq i (1+ i)))
                (t (when (and nested (> depth 0)) (aset out i ?\s))
                   (setq i (1+ i)))))))
    out))

(defun app-server--mysql-literal (value)
  "VALUE as MySQL text that is never read as SQL: text goes as hex."
  (cond ((null value) "NULL")
        ((eq value t) "TRUE")
        ((integerp value) (number-to-string value))
        ((floatp value)
         (when (or (isnan value) (= value 1.0e+INF) (= value -1.0e+INF))
           (signal 'app-server-sql-error (list nil (format "Not a number SQL can keep: %S" value))))
         (format "%.17g" value))
        ((stringp value)
         (let ((bytes (if (multibyte-string-p value) (encode-coding-string value 'utf-8) value)))
           (if (and (not (multibyte-string-p value)) (string-match-p "[\x80-\xff]" value))
               ;; Bytes, not text.
               (concat "X'" (mapconcat (lambda (byte) (format "%02X" byte)) bytes "") "'")
             (concat "CONVERT(X'" (mapconcat (lambda (byte) (format "%02X" byte)) bytes "")
                     "' USING utf8mb4)"))))
        (t (signal 'app-server-sql-error (list nil (format "Not a value for SQL: %S" value))))))

(defun app-server--mysql-bind (sql params)
  "SQL with each ? (outside quotes and comments) replaced by one of PARAMS."
  (let ((mask (app-server--sql-mask sql)) (parts nil) (from 0) (start 0))
    (while (string-match "\\?" mask from)
      (let ((at (match-beginning 0)))
        (unless params
          (signal 'app-server-sql-error (list nil (format "More ? than parameters in: %s" sql))))
        (push (substring sql start at) parts)
        (push (app-server--mysql-literal (pop params)) parts)
        (setq start (1+ at) from (1+ at))))
    (when params
      (signal 'app-server-sql-error (list nil (format "More parameters than ? in: %s" sql))))
    (push (substring sql start) parts)
    (apply #'concat (nreverse parts))))

(defun app-server--mysql-json-select (sql)
  "SQL, a SELECT, made to give each row as one JSON array.
Its columns' aliases go (rows are lists); a * is refused."
  (let* ((nested (app-server--sql-mask sql t))
         (case-fold-search t)
         (word "\\(?:\\`\\|[^A-Za-z0-9_$]\\)"))
    (unless (string-match "\\`[ \t\n]*SELECT[ \t\n]+\\(\\(?:DISTINCT\\|ALL\\)[ \t\n]+\\)?" nested)
      (signal 'app-server-sql-error (list nil (format "Not a SELECT: %s" sql))))
    (let* ((head (substring sql 0 (match-end 0)))
           (list-start (match-end 0))
           (from (and (string-match (concat word "\\(FROM\\)[^A-Za-z0-9_$]") nested list-start)
                      (match-beginning 1)))
           (list-end (or from (length sql)))
           (items nil)
           (start list-start))
      (while (< start list-end)
        (let* ((comma (and (string-match "," nested start) (< (match-beginning 0) list-end)
                           (match-beginning 0)))
               (end (or comma list-end))
               (item (substring sql start end))
               (masked (substring nested start end)))
          (when (string-match-p "\\`[ \t\n]*\\(?:[A-Za-z0-9_$`.]*\\.\\)?\\*[ \t\n]*\\'" masked)
            (signal 'app-server-sql-error (list nil (format "Name the columns, not *: %s" sql))))
          (when (string-match "[ \t\n]+AS[ \t\n]+[^ \t\n]+[ \t\n]*\\'" masked)
            (setq item (substring item 0 (match-beginning 0))))
          (push (string-trim item) items)
          (setq start (if comma (1+ comma) list-end))))
      (concat head "JSON_ARRAY(" (mapconcat #'identity (nreverse items) ", ") ") "
              (substring sql list-end)))))

(defun app-server--mysql-open ()
  "A new connection: a `mysql' process that reads statements."
  (unless (file-readable-p (expand-file-name app-server-mysql))
    (signal 'app-server-sql-error (list nil (format "Cannot read the MySQL option file %s" app-server-mysql))))
  (let* ((errors (generate-new-buffer " *app-server-mysql-errors*"))
         (process (make-process
                   :name "app-server-mysql"
                   :buffer (generate-new-buffer " *app-server-mysql*")
                   :stderr errors
                   :command (list app-server-mysql-program
                                  (concat "--defaults-extra-file=" (expand-file-name app-server-mysql))
                                  "--batch" "--raw" "--skip-column-names" "--unbuffered")
                   :coding 'utf-8 :connection-type 'pipe :noquery t
                   :sentinel #'ignore)))
    (process-put process :errors errors)
    process))

(defun app-server--mysql-close (process)
  "End the connection PROCESS: the end of its input, then its buffers."
  (when (process-live-p process)
    (ignore-errors (process-send-eof process))
    (let ((deadline (+ (float-time) 2)))
      (while (and (process-live-p process) (< (float-time) deadline))
        (accept-process-output process 0.02)))
    (when (process-live-p process) (delete-process process)))
  (let ((errors (process-get process :errors)))
    (when (buffer-live-p errors)
      (let ((stderr (get-buffer-process errors))) (when stderr (delete-process stderr)))
      (kill-buffer errors)))
  (when (buffer-live-p (process-buffer process)) (kill-buffer (process-buffer process))))

(defun app-server--mysql-failure (process)
  "The error of PROCESS, which ended: (CODE MESSAGE) from what it said."
  (let ((errors (process-get process :errors)) (text ""))
    ;; What it wrote to its error output may come after its end.
    (let ((stderr (and (buffer-live-p errors) (get-buffer-process errors)))
          (deadline (+ (float-time) 1)))
      (while (and stderr (process-live-p stderr) (< (float-time) deadline))
        (accept-process-output stderr 0.02)))
    (when (buffer-live-p errors)
      (setq text (string-trim (with-current-buffer errors (buffer-string)))))
    (if (string-match "ERROR \\([0-9]+\\)[^:]*: \\(.*\\)" text)
        (list (string-to-number (match-string 1 text)) (match-string 2 text))
      (list nil (if (string-empty-p text) "The MySQL client ended" text)))))

(defun app-server--mysql-run (process sql)
  "Run SQL, one statement or several, on PROCESS; the lines it printed.
The end mark comes after the last: a statement such as ROW_COUNT() sees
the one before it."
  (let* ((mark (format "app-server-sql-%d-%d" (emacs-pid) (cl-incf app-server--mysql-count)))
         (buffer (process-buffer process))
         (start (with-current-buffer buffer (point-max)))
         (sql (replace-regexp-in-string "[; \t\n]+\\'" "" sql))
         (deadline (+ (float-time) app-server-mysql-timeout))
         end)
    (process-send-string process (concat sql ";\nSELECT '" mark "';\n"))
    (while (and (not end) (process-live-p process) (< (float-time) deadline))
      (accept-process-output process 0.05)
      (with-current-buffer buffer
        (save-excursion
          (goto-char start)
          (when (re-search-forward (concat "^" (regexp-quote mark) "$") nil t)
            (setq end (match-beginning 0))))))
    ;; A last look: the end mark may have come with the end of the process.
    (unless end
      (with-current-buffer buffer
        (save-excursion
          (goto-char start)
          (when (re-search-forward (concat "^" (regexp-quote mark) "$") nil t)
            (setq end (match-beginning 0))))))
    (cond (end (split-string (with-current-buffer buffer (buffer-substring-no-properties start end)) "\n" t))
          ((process-live-p process)
           (delete-process process)
           (signal 'app-server-sql-error (list nil (format "MySQL did not answer in %d seconds" app-server-mysql-timeout))))
          (t (signal 'app-server-sql-error (app-server--mysql-failure process))))))

(defun app-server--mysql-call (statements)
  "Run STATEMENTS (strings), one after the other in one go, on the
connection of the moment; the lines they printed."
  (cond
   ((and app-server--mysql-process (process-live-p app-server--mysql-process))
    (condition-case err
        (app-server--mysql-run app-server--mysql-process
                               (mapconcat (lambda (sql) (replace-regexp-in-string "[; \t\n]+\\'" "" sql))
                                          statements ";\n"))
      (error
       ;; A connection that failed is gone: so is its transaction.
       (app-server--mysql-close app-server--mysql-process)
       (setq app-server--mysql-process nil)
       (signal (car err) (cdr err)))))
   (app-server-mysql-keep
    (setq app-server--mysql-process (app-server--mysql-open))
    (app-server--mysql-call statements))
   (t (let ((process (app-server--mysql-open)))
        (unwind-protect
            (app-server--mysql-run process
                                   (mapconcat (lambda (sql) (replace-regexp-in-string "[; \t\n]+\\'" "" sql))
                                              statements ";\n"))
          (app-server--mysql-close process))))))

(defun app-server--json-row (line)
  (let ((json-array-type 'list) (json-object-type 'plist) (json-key-type 'keyword)
        (json-null nil) (json-false nil))
    (json-read-from-string line)))

(defun app-server-sql-select (sql &optional params)
  "The rows of the SELECT statement SQL, a list of lists.
Each ? in SQL is one of PARAMS, in order: a string, a number, t or nil
\(NULL).  Values come back as strings, numbers or nil.  On MySQL a column's
alias is dropped (ORDER BY cannot use it) and * has to be the columns'
names."
  (if (eq (app-server-sql-backend) 'mysql)
      (mapcar #'app-server--json-row
              (app-server--mysql-call
               (list (app-server--mysql-bind (app-server--mysql-json-select sql) params))))
    (sqlite-select (app-server-database) sql params)))

(defun app-server-sql-execute (sql &optional params)
  "Run the statement SQL with PARAMS (see `app-server-sql-select').
Returns the number of rows it changed."
  (if (eq (app-server-sql-backend) 'mysql)
      (car (app-server--json-row
            (car (last (app-server--mysql-call
                        (list (app-server--mysql-bind sql params) "SELECT JSON_ARRAY(ROW_COUNT())"))))))
    (sqlite-execute (app-server-database) sql params)))

(defun app-server-sql-insert (sql &optional params)
  "Run the INSERT statement SQL with PARAMS; the id it gave the new row."
  (if (eq (app-server-sql-backend) 'mysql)
      (car (app-server--json-row
            (car (last (app-server--mysql-call
                        (list (app-server--mysql-bind sql params) "SELECT JSON_ARRAY(LAST_INSERT_ID())"))))))
    (let ((database (app-server-database)))
      (sqlite-execute database sql params)
      (caar (sqlite-select database "SELECT last_insert_rowid()")))))

(defmacro app-server-sql-transaction (&rest body)
  "Run BODY as one transaction: all of its changes, or none.
An error in BODY undoes them and goes on; so does the end of the process
in the middle (MySQL drops the connection, SQLite its journal)."
  (declare (indent 0) (debug t))
  `(app-server--sql-transaction (lambda () ,@body)))

(defvar app-server--sql-transaction nil "Non-nil inside `app-server-sql-transaction'.")

(defun app-server--sql-transaction (function)
  (cond
   ;; Inside one already: it is part of that one.
   (app-server--sql-transaction (funcall function))
   ((eq (app-server-sql-backend) 'mysql)
    (let* ((own (not (and app-server--mysql-process (process-live-p app-server--mysql-process))))
           (app-server--mysql-process (if own (app-server--mysql-open) app-server--mysql-process))
           (app-server--sql-transaction t)
           (done nil))
      (unwind-protect
          (progn
            (app-server--mysql-call (list "START TRANSACTION"))
            (prog1 (funcall function)
              (app-server--mysql-call (list "COMMIT"))
              (setq done t)))
        (let ((process app-server--mysql-process))
          ;; A connection that failed has gone, and its transaction with it.
          (when (and (not done) process (process-live-p process))
            (ignore-errors (app-server--mysql-run process "ROLLBACK")))
          (when (and own process) (app-server--mysql-close process))))))
   (t
    (let ((database (app-server-database)) (app-server--sql-transaction t) (done nil))
      (sqlite-transaction database)
      (unwind-protect
          (prog1 (funcall function)
            (sqlite-commit database)
            (setq done t))
        (unless done (sqlite-rollback database)))))))

(defvar app-server-session-days 30 "How long a session lasts.")
(defvar app-server-session-cookie "session" "The name of the session's cookie.")
(defvar app-server-attempts-max 5
  "How many failures are let through for one name or address.")
(defvar app-server-attempts-seconds 600
  "The time in which `app-server-attempts-max' failures stop further tries.")

(defvar app-server--memory (make-hash-table :test 'equal)
  "Sessions and attempts, in an Emacs without SQLite or MySQL.")
(defvar app-server--own-tables nil "Non-nil once the tables of server.db exist.")

(defun app-server--own-database ()
  "Where sessions and attempts are: `mysql' (`app-server-mysql'), the
SQLite database server.db, or nil (this Emacs's memory) without either."
  (cond
   (app-server-mysql 'mysql)
   ((and (fboundp 'sqlite-available-p) (sqlite-available-p))
    (let ((database (app-server-database "server")))
      (unless app-server--own-tables
        (sqlite-execute database "CREATE TABLE IF NOT EXISTS sessions (
                                    token TEXT PRIMARY KEY, visitor TEXT NOT NULL, expires REAL NOT NULL)")
        (sqlite-execute database "CREATE TABLE IF NOT EXISTS attempts (name TEXT NOT NULL, at REAL NOT NULL)")
        (sqlite-execute database "CREATE INDEX IF NOT EXISTS attempts_name ON attempts (name)")
        (sqlite-execute database "CREATE TABLE IF NOT EXISTS jobs (
                                    name TEXT PRIMARY KEY, last_run REAL, running_until REAL)")
        (setq app-server--own-tables t))
      database))))

(defun app-server--own-table (database name)
  "The table NAME (`sessions' or `attempts') of DATABASE."
  (if (eq database 'mysql) (format "app_server_%s" name) (symbol-name name)))

(defun app-server--own-mysql-tables ()
  (app-server-sql-execute "CREATE TABLE IF NOT EXISTS app_server_sessions (
                             token CHAR(64) NOT NULL PRIMARY KEY, visitor TEXT NOT NULL,
                             expires DOUBLE NOT NULL) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4")
  (app-server-sql-execute "CREATE TABLE IF NOT EXISTS app_server_attempts (
                             name CHAR(64) NOT NULL, at DOUBLE NOT NULL,
                             KEY app_server_attempts_name (name)) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4")
  (app-server-sql-execute "CREATE TABLE IF NOT EXISTS app_server_data (
                             name VARCHAR(64) NOT NULL PRIMARY KEY, value LONGTEXT NOT NULL,
                             updated DOUBLE NOT NULL) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4")
  (app-server-sql-execute "CREATE TABLE IF NOT EXISTS app_server_jobs (
                             name VARCHAR(64) NOT NULL PRIMARY KEY, last_run DOUBLE NULL,
                             running_until DOUBLE NULL) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4"))

(defun app-server--own-sql (database kind sql &optional params)
  "Run SQL with PARAMS on DATABASE (`app-server--own-database'): KIND is
`select' (the rows) or `execute'.  The MySQL tables are made at need."
  (cl-flet ((run () (if (eq kind 'select) (app-server-sql-select sql params) (app-server-sql-execute sql params))))
    (if (eq database 'mysql)
        (condition-case err
            (run)
          (app-server-sql-error
           ;; 1146: no such table.  The first use on a new database.
           (if (eql (nth 1 err) 1146)
               (progn (app-server--own-mysql-tables) (run))
             (signal (car err) (cdr err)))))
      (if (eq kind 'select) (sqlite-select database sql params) (sqlite-execute database sql params)))))

(defun app-server--print (data)
  (let ((print-length nil) (print-level nil)) (prin1-to-string data)))

(defun app-server-session-start (visitor &optional days)
  "Start a session for VISITOR: from now on `app-server-session' is VISITOR.
VISITOR is Lisp data that says who it is: a name, a number, a plist.
The browser gets a cookie with a random name for the session, good for
DAYS (default `app-server-session-days'); the server keeps a hash of
that name, so its database does not hold what would let someone in.
Returns VISITOR."
  (let* ((token (app-server-token))
         (key (secure-hash 'sha256 token))
         (seconds (* 86400 (or days app-server-session-days)))
         (expires (+ (float-time) seconds))
         (database (app-server--own-database)))
    (if database
        (let ((table (app-server--own-table database 'sessions)))
          ;; Also the moment to forget what has run out.
          (app-server--own-sql database 'execute (format "DELETE FROM %s WHERE expires < ?" table)
                               (list (float-time)))
          (app-server--own-sql database 'execute
                               (format "INSERT INTO %s (token, visitor, expires) VALUES (?, ?, ?)" table)
                               (list key (app-server--print visitor) expires)))
      (puthash (concat "session " key) (cons (app-server--print visitor) expires) app-server--memory))
    (app-server-set-cookie app-server-session-cookie token :max-age (round seconds))
    visitor))

(defun app-server--session-key ()
  (let ((token (app-server-cookie app-server-session-cookie)))
    (and token (string-match-p "\\`[0-9a-f]\\{64\\}\\'" token) (secure-hash 'sha256 token))))

(defun app-server-session ()
  "Who the visitor of the request being answered is, or nil if not signed in.
The value is what `app-server-session-start' was given."
  (let* ((key (app-server--session-key))
         (database (and key (app-server--own-database)))
         (found (cond ((not key) nil)
                      (database (car (app-server--own-sql
                                      database 'select
                                      (format "SELECT visitor, expires FROM %s WHERE token = ?"
                                              (app-server--own-table database 'sessions))
                                      (list key))))
                      (t (let ((kept (gethash (concat "session " key) app-server--memory)))
                           (and kept (list (car kept) (cdr kept))))))))
    (and found (> (nth 1 found) (float-time))
         (car (read-from-string (nth 0 found))))))

(defun app-server-session-end ()
  "End the session of the request being answered (sign out)."
  (let* ((key (app-server--session-key))
         (database (and key (app-server--own-database))))
    (cond ((not key))
          (database (app-server--own-sql database 'execute
                                         (format "DELETE FROM %s WHERE token = ?"
                                                 (app-server--own-table database 'sessions))
                                         (list key)))
          (t (remhash (concat "session " key) app-server--memory))))
  (app-server-delete-cookie app-server-session-cookie)
  nil)

(defun app-server-session-end-all (visitor)
  "End every session of VISITOR, on every device.
For when a password was changed: whoever knew the old one is out."
  (let ((database (app-server--own-database))
        (printed (app-server--print visitor)))
    (if database
        (app-server--own-sql database 'execute
                             (format "DELETE FROM %s WHERE visitor = ?" (app-server--own-table database 'sessions))
                             (list printed))
      (maphash (lambda (key kept)
                 (when (and (string-prefix-p "session " key) (equal (car kept) printed))
                   (remhash key app-server--memory)))
               app-server--memory)))
  nil)

(defun app-server-visitor-address ()
  "The address the visitor comes from, as the reverse proxy says, or nil.
Without a proxy there is none to tell apart: everyone is this machine."
  (let ((forwarded (app-server-header "x-forwarded-for")))
    ;; The last entry is the one the proxy next to this server wrote.
    (and forwarded (car (last (split-string forwarded "," t "[ \t]+"))))))

(defun app-server--attempt-names (names)
  "NAMES (strings, or nil for none) as they are kept: hashed."
  (mapcar (lambda (name) (secure-hash 'sha256 (encode-coding-string (downcase name) 'utf-8)))
          (delq nil (copy-sequence names))))

(defun app-server--attempts (name since)
  "The times of the failures for NAME (hashed) after SINCE, oldest first."
  (let ((database (app-server--own-database)))
    (if database
        (mapcar #'car (app-server--own-sql
                       database 'select
                       (format "SELECT at FROM %s WHERE name = ? AND at > ? ORDER BY at"
                               (app-server--own-table database 'attempts))
                       (list name since)))
      (seq-filter (lambda (at) (> at since)) (gethash (concat "attempts " name) app-server--memory)))))

(defun app-server-attempts-check (&rest names)
  "Refuse the request (429) if there were too many failures for one of NAMES.
NAMES are strings that say whose attempt this is: the account's name,
the visitor's address (`app-server-visitor-address'); nil is none.  Too
many is `app-server-attempts-max' within `app-server-attempts-seconds'."
  (let ((since (- (float-time) app-server-attempts-seconds)))
    (dolist (name (app-server--attempt-names names))
      (let ((failures (app-server--attempts name since)))
        (when (>= (length failures) app-server-attempts-max)
          (let ((wait (max 1 (ceiling (- (+ (car failures) app-server-attempts-seconds) (float-time))))))
            (app-server-set-header "Retry-After" (number-to-string wait))
            (app-server-refuse (format "Too many attempts. Try again in %d minutes" (ceiling wait 60.0))
                               429)))))))

(defun app-server-attempts-failed (&rest names)
  "Note a failed attempt for each of NAMES (see `app-server-attempts-check')."
  (let ((database (app-server--own-database))
        (now (float-time)))
    (when database
      (app-server--own-sql database 'execute
                           (format "DELETE FROM %s WHERE at < ?" (app-server--own-table database 'attempts))
                           (list (- now app-server-attempts-seconds))))
    (dolist (name (app-server--attempt-names names))
      (if database
          (app-server--own-sql database 'execute
                               (format "INSERT INTO %s (name, at) VALUES (?, ?)"
                                       (app-server--own-table database 'attempts))
                               (list name now))
        (puthash (concat "attempts " name)
                 (append (app-server--attempts name (- now app-server-attempts-seconds)) (list now))
                 app-server--memory))))
  nil)

(defun app-server-attempts-clear (&rest names)
  "Forget the failures for NAMES: for the account that has just signed in."
  (let ((database (app-server--own-database)))
    (dolist (name (app-server--attempt-names names))
      (if database
          (app-server--own-sql database 'execute
                               (format "DELETE FROM %s WHERE name = ?" (app-server--own-table database 'attempts))
                               (list name))
        (remhash (concat "attempts " name) app-server--memory))))
  nil)

;;;; Scheduled work

(defvar app-server-jobs nil
  "The jobs of the application: ((NAME . SPEC) ...); see `app-server-defjob'.")

(defvar app-server-job-timeout 600
  "Seconds a run of a job may take.  After that another run may start
(the process of this one was ended, say).")

(defvar app-server-job-slack 30
  "Seconds a job may run before it is due.  Cron starts on the minute and
Emacs a moment later, so a job of 900 seconds from cron every 15 minutes
would otherwise find itself a moment too early, and run every 30.")

(defun app-server-defjob (name &rest spec)
  "Make NAME, a symbol, a job of the application: something to do every so often.
SPEC is a plist:

:every SECONDS     how often it is due
:function F        what it does: (F) returns when it is done; or, with
:later t,          (F DONE): F starts the work and calls DONE when it has
                   finished (after `app-server-fetch', say)

There is no resident process to run it with a timer on every host: a
host runs the due jobs, each at most once at a time however many
processes ask (the database keeps a lock for it):

  a native Emacs (run.sh)      every minute, by itself
  a shared host (CGI)          APP-DIR/job.sh, from cron (tools/serve-cgi.el)
  the studio's browser tab     not at all

A job is not given a request: no session, no cookie.  A job that fails
is logged and is due again after SECONDS.  Returns NAME."
  (unless (and (natnump (plist-get spec :every)) (functionp (plist-get spec :function)))
    (error "A job needs :every SECONDS and :function"))
  (setf (alist-get name app-server-jobs) spec)
  name)

(defun app-server--job-claim (name every force)
  "Start the run of job NAME if it is due (or FORCE) and no run is under
way: non-nil if this process has it now."
  (let* ((database (app-server--own-database))
         (now (float-time))
         (key (symbol-name name)))
    (if database
        (let ((table (if (eq database 'mysql) "app_server_jobs" "jobs")))
          (app-server--own-sql database 'execute
                               (format (if (eq database 'mysql) "INSERT IGNORE INTO %s (name) VALUES (?)"
                                         "INSERT OR IGNORE INTO %s (name) VALUES (?)")
                                       table)
                               (list key))
          ;; One UPDATE: of two processes that ask at once, one changes the row.
          (eql 1 (app-server--own-sql
                  database 'execute
                  (format "UPDATE %s SET running_until = ? WHERE name = ?
                             AND (running_until IS NULL OR running_until < ?)
                             AND (? OR last_run IS NULL OR last_run <= ?)" table)
                  (list (+ now app-server-job-timeout) key now (if force 1 0) (- (+ now app-server-job-slack) every)))))
      ;; No database: a directory is made by one process only.
      (let ((lock (expand-file-name (concat "jobs/" key ".lock") app-server-data-directory))
            (last (cdr (assoc key (app-server-read "jobs" nil)))))
        (make-directory (file-name-directory lock) t)
        (when (and (file-directory-p lock)
                   (> (- now (float-time (file-attribute-modification-time (file-attributes lock))))
                      app-server-job-timeout))
          (ignore-errors (delete-directory lock)))
        (and (or force (null last) (<= last (- (+ now app-server-job-slack) every)))
             (condition-case nil (progn (make-directory lock) t) (file-already-exists nil)))))))

(defun app-server--job-done (name started)
  "Note that the run of job NAME, STARTED then, has ended.
The next is due from its start: a job of 900 seconds from cron every 15
minutes runs every 15 minutes, whatever it takes."
  (let ((database (app-server--own-database))
        (key (symbol-name name)))
    (if database
        (app-server--own-sql database 'execute
                             (format "UPDATE %s SET running_until = NULL, last_run = ? WHERE name = ?"
                                     (if (eq database 'mysql) "app_server_jobs" "jobs"))
                             (list started key))
      (let ((runs (app-server-read "jobs" nil)))
        (setf (alist-get key runs nil nil #'equal) started)
        (app-server-write "jobs" runs)
        (ignore-errors (delete-directory (expand-file-name (concat "jobs/" key ".lock") app-server-data-directory)))))))

(defun app-server--job-start (name spec force finish)
  "Run job NAME (SPEC: see `app-server-defjob') if it is due or FORCE and
no other process runs it; call FINISH with the result: `done', `not-due'
or the message of the failure."
  (if (not (app-server--job-claim name (plist-get spec :every) force))
      (funcall finish 'not-due)
    (let* ((started (float-time))
           (ended nil)
           (end (lambda (&optional failure)
                  (unless ended
                    (setq ended t)
                    (ignore-errors (app-server--job-done name started))
                    (message "app-server: job %s %s in %dms" name
                             (if failure (format "failed: %s" failure) "done")
                             (round (* 1000 (- (float-time) started))))
                    (funcall finish (or failure 'done))))))
      (condition-case err
          (if (plist-get spec :later)
              (funcall (plist-get spec :function)
                       (lambda (&optional problem)
                         (funcall end (and problem (format "%s" problem)))))
            (funcall (plist-get spec :function))
            (funcall end))
        (error (funcall end (error-message-string err)))))))

(defun app-server-run-jobs (&optional only no-wait)
  "Run the jobs that are due; with ONLY (a symbol), that job, due or not.
Each runs where no other process runs it.  Returns ((NAME . RESULT) ...):
RESULT is `done', `not-due' (or under way elsewhere) or the message of
the failure; it waits for the jobs that finish later (`:later'), at
most `app-server-job-timeout' seconds.  With NO-WAIT it starts them and
returns nil at once: a server that keeps answering requests meanwhile."
  (let ((results nil) (pending 0) (started (float-time)))
    (dolist (entry (reverse app-server-jobs))
      (let ((name (car entry)))
        (when (or (not only) (eq only name))
          (setq pending (1+ pending))
          (app-server--job-start name (cdr entry) (and only t)
                                 (lambda (result)
                                   (setq pending (1- pending))
                                   (push (cons name result) results))))))
    (unless no-wait
      (while (and (> pending 0) (< (- (float-time) started) app-server-job-timeout))
        (accept-process-output nil 0.05))
      (nreverse results))))

(defun app-server-cleanup ()
  "Forget what has run out: sessions, old failed attempts, and uploads
that a request ended in the middle of left half written.  A job of every
application (`app-server-jobs')."
  (let ((database (app-server--own-database))
        (now (float-time)))
    (when database
      (app-server--own-sql database 'execute
                           (format "DELETE FROM %s WHERE expires < ?" (app-server--own-table database 'sessions))
                           (list now))
      (app-server--own-sql database 'execute
                           (format "DELETE FROM %s WHERE at < ?" (app-server--own-table database 'attempts))
                           (list (- now app-server-attempts-seconds)))))
  (let ((uploads (expand-file-name "uploads/" app-server-data-directory)))
    (when (file-directory-p uploads)
      (dolist (file (directory-files uploads t "\\`[^.]"))
        (when (> (- (float-time) (float-time (file-attribute-modification-time (file-attributes file)))) 86400)
          (ignore-errors (delete-file file)))))))

(app-server-defjob 'app-server-cleanup :every 3600 :function #'app-server-cleanup)

;;;; Answering later

(cl-defstruct (app-server--deferred (:constructor app-server--deferred-create))
  function)

(defvar app-server-deferred-timeout 30
  "Seconds after which a deferred request is answered with an error (504).")

(defvar app-server--fail nil
  "While code of a deferred request runs: the function that fails that request.")

(defun app-server-defer (function)
  "Return this from `app-server-handle' to answer the request later.
FUNCTION is called at once with two functions, RESPOND and FAIL.  It
starts whatever the answer depends on (`app-server-fetch',
`app-server-after') and returns; the server then goes on with other
requests.  The request is answered when (funcall RESPOND DATA) is
called, or (funcall FAIL MESSAGE [STATUS]); whichever comes first
counts.  An error in the functions that run later fails the request, and
so does `app-server-deferred-timeout'."
  (app-server--deferred-create :function function))

(defun app-server--guard (function)
  "FUNCTION, wrapped for running later on behalf of the current request.
An error it signals fails that request instead of being lost."
  (let ((fail app-server--fail)
        (request app-server--request))
    (lambda (&rest arguments)
      (condition-case err
          (let ((app-server--fail fail)
                (app-server--request request))
            (apply function arguments))
        (app-server-refusal
         (when fail (funcall fail (nth 1 err) (nth 2 err))))
        (file-missing
         (if fail
             (funcall fail (app-server--file-missing-text err) 404)
           (message "app-server: %s" (error-message-string err))))
        (error
         (if fail
             (funcall fail (app-server--error-text err))
           (message "app-server: %s" (error-message-string err))))))))

;; What there is to wait for.  The two hosts do these differently: a native
;; Emacs has timers and its own HTTP client; in a browser tab the page does
;; both (see "For the studio" below).

(defvar app-server-after-function
  (lambda (seconds function) (run-at-time seconds nil function))
  "Function of (SECONDS FUNCTION) that calls FUNCTION after SECONDS.")

(defvar app-server-fetch-function #'app-server--fetch
  "Function of (URL METHOD HEADERS BODY THEN CATCH) that makes an HTTP request.
THEN is called with (:status N :ok BOOLEAN :text STRING), or CATCH with a
message when there was no response.")

(defvar app-server-curl-program "curl"
  "The program that fetches https: for an Emacs without GnuTLS.")

(defvar app-server-run-function #'app-server--make-process
  "Function of (COMMAND INPUT THEN) that runs a program; see `app-server-run'.")

(defun app-server-after (seconds function)
  "Call FUNCTION, without arguments, after SECONDS.  Returns at once."
  (funcall app-server-after-function seconds (app-server--guard function))
  nil)

(defun app-server-fetch (url &rest options)
  "Make an HTTP request to URL; return at once.  OPTIONS is a plist:

:method STRING   \"GET\" by default
:headers PLIST   (:content-type \"application/json\")
:body STRING
:then FUNCTION   (RESPONSE), a plist (:status 200 :ok t :text \"...\");
                 an HTTP error status is a response too, with :ok nil
:catch FUNCTION  (MESSAGE), when there was no response at all; without
                 it, that fails the deferred request"
  (let ((then (plist-get options :then))
        (catch (plist-get options :catch)))
    (funcall app-server-fetch-function url
             (or (plist-get options :method) "GET")
             (plist-get options :headers)
             (plist-get options :body)
             (app-server--guard (or then #'ignore))
             (app-server--guard (or catch (lambda (message) (error "%s: %s" url message))))))
  nil)

(defun app-server-run (command &rest options)
  "Run a program without waiting for it; return at once.
COMMAND is a list: the program and its arguments (no shell reads it).
OPTIONS is a plist:

:input STRING    what the program reads
:then FUNCTION   (RESULT), a plist (:status 0 :output \"...\"), when the
                 program has ended

This is how a server gives long work to another process, a second Emacs
for instance, and stays free meanwhile.  Only a native Emacs can: in the
studio's browser tab there are no programs, and the request fails."
  (funcall app-server-run-function command (plist-get options :input)
           (app-server--guard (or (plist-get options :then) #'ignore)))
  nil)

(defun app-server--make-process (command input then)
  "`app-server-run' for a native Emacs."
  (let* ((buffer (generate-new-buffer " *app-server-run*"))
         (process
          (make-process
           :name "app-server-run" :buffer buffer :command command :connection-type 'pipe
           :noquery t :coding 'utf-8
           :sentinel (lambda (process _event)
                       (unless (process-live-p process)
                         (let ((output (with-current-buffer buffer (buffer-string))))
                           (kill-buffer buffer)
                           (funcall then (list :status (process-exit-status process) :output output))))))))
    (when input (process-send-string process input))
    (process-send-eof process)))

(defun app-server--fetch (url method headers body then catch)
  "`app-server-fetch' for a native Emacs: url.el, or for https: in an
Emacs without GnuTLS (that of a shared host, say), the curl program."
  (if (and (string-prefix-p "https:" url)
           (not (and (fboundp 'gnutls-available-p) (gnutls-available-p)))
           (executable-find app-server-curl-program))
      (app-server--curl-fetch url method headers body then catch)
    (app-server--url-fetch url method headers body then catch)))

(defun app-server--curl-fetch (url method headers body then catch)
  "`app-server-fetch' through the curl program, without waiting."
  (let* ((buffer (generate-new-buffer " *app-server-curl*"))
         (arguments
          (append (list "--silent" "--show-error" "--location" "--max-redirs" "5" "--max-time" "30"
                        "--request" method "--output" "-" "--write-out" "\n%{http_code}")
                  (let (list)
                    (while headers
                      (push (format "%s: %s" (substring (symbol-name (car headers)) 1)
                                    (replace-regexp-in-string "[\r\n]" " " (format "%s" (cadr headers))))
                            list)
                      (push "--header" list)
                      (setq headers (cddr headers)))
                    list)
                  (and body (list "--data-binary" "@-"))
                  (list "--url" url)))
         (process
          (make-process
           :name "app-server-curl" :buffer buffer :command (cons app-server-curl-program arguments)
           :coding 'binary :connection-type 'pipe :noquery t
           :sentinel
           (lambda (process _event)
             (unless (process-live-p process)
               (let ((output (with-current-buffer buffer (buffer-string)))
                     (status (process-exit-status process)))
                 (kill-buffer buffer)
                 (if (and (eq status 0) (string-match "\n\\([0-9][0-9][0-9]\\)\\'" output))
                     (let ((code (string-to-number (match-string 1 output))))
                       (funcall then (list :status code :ok (and (>= code 200) (< code 300) t)
                                           :text (decode-coding-string (substring output 0 (match-beginning 0))
                                                                       'utf-8))))
                   (funcall catch (format "curl: %s"
                                          (string-trim (replace-regexp-in-string "\n[0-9]*\\'" "" output)))))))))))
    (when body (process-send-string process (encode-coding-string body 'utf-8)))
    (process-send-eof process)))

(defun app-server--url-fetch (url method headers body then catch)
  "`app-server-fetch' for a native Emacs: url.el, without waiting."
  (require 'url)
  (let ((url-request-method method)
        (url-request-data (and body (encode-coding-string body 'utf-8)))
        (url-request-extra-headers
         (let (list)
           (while headers
             (push (cons (substring (symbol-name (car headers)) 1) (format "%s" (cadr headers))) list)
             (setq headers (cddr headers)))
           list)))
    (url-retrieve
     url
     (lambda (status)
       (let ((buffer (current-buffer))
             (code (and (boundp 'url-http-response-status) url-http-response-status))
             (end (and (boundp 'url-http-end-of-headers) url-http-end-of-headers)))
         (unwind-protect
             (if (and (integerp code) end)
                 (funcall then (list :status code :ok (and (>= code 200) (< code 300) t)
                                     :text (decode-coding-string
                                            (buffer-substring-no-properties (min (1+ end) (point-max)) (point-max))
                                            'utf-8)))
               (funcall catch (format "%s" (or (plist-get status :error) "no response"))))
           (kill-buffer buffer))))
     nil t t)))

;;;; Requests

(defun app-server-respond (method path body &optional later headers upload)
  "Answer one request with `app-server-handle'.
PATH may end in a query (?name=value&...).  HEADERS is the request's
headers, an alist (NAME . VALUE) with the names in lower case.  The value
is a vector [STATUS TEXT HEADERS]: the HTTP status, the response body
(printed Lisp data) and the headers the handler asked for, a list of
\(NAME . VALUE).  When the handler answers with a file
\(`app-server-send-file'), TEXT is (:file FILE :type TYPE :name NAME).
UPLOAD is (:file FILE :size BYTES :type STRING) when the body went into a
file (`app-server-upload-accept'); BODY is then empty.

If the handler defers its answer (`app-server-defer'), the value is nil
and LATER, a function of (STATUS TEXT HEADERS), is called when the answer
is there.  A host that passes no LATER cannot wait: the request fails."
  (let* ((print-length nil) (print-level nil)
         (question (string-search "?" path))
         (app-server--request
          (app-server--request-create
           :parameters (and question (url-parse-query-string (substring path (1+ question))))
           :headers headers :upload upload))
         (path (if question (substring path 0 question) path))
         (answer (lambda (status data)
                   (vector status (app-server--answer-body data)
                           (reverse (app-server--request-response-headers app-server--request))))))
    (condition-case err
        (if (fboundp 'app-server-handle)
            (let ((value (funcall 'app-server-handle method path body)))
              (cond ((not (app-server--deferred-p value)) (funcall answer 200 value))
                    ((not later) (funcall answer 500 "This server cannot answer later"))
                    (t (app-server--start-deferred value later))))
          (funcall answer 404 "This application has no server.el"))
      (app-server-refusal (funcall answer (nth 2 err) (nth 1 err)))
      (file-missing (funcall answer 404 (app-server--file-missing-text err)))
      (error (funcall answer 400 (app-server--error-text err))))))

(defun app-server--start-deferred (deferred later)
  "Run DEFERRED's function; LATER (STATUS TEXT HEADERS) gets the answer, once.
Returns nil, or [STATUS TEXT HEADERS] if the function answered right away."
  (let* ((answered nil)
         (request app-server--request)
         (timeout nil)
         (answer (lambda (status data)
                   (unless answered
                     (setq answered t)
                     (when timeout (cancel-timer timeout))
                     (funcall later status (app-server--answer-body data)
                              (reverse (app-server--request-response-headers request))))))
         (respond (lambda (data) (funcall answer 200 data)))
         (fail (lambda (message &optional status) (funcall answer (or status 400) message)))
         (now nil))
    ;; Until the function has returned, an answer is the value of
    ;; `app-server-respond' itself rather than something for LATER.
    (let ((later-for-real later))
      (setq later (lambda (status text headers) (setq now (vector status text headers))))
      (let ((app-server--fail fail))
        (condition-case err
            (funcall (app-server--deferred-function deferred) respond fail)
          (app-server-refusal (funcall fail (nth 1 err) (nth 2 err)))
          (file-missing (funcall fail (app-server--file-missing-text err) 404))
          (error (funcall fail (app-server--error-text err))))
        ;; In a browser tab the page gives up by itself.
        (unless (or answered app-server--tab)
          (setq timeout (run-at-time app-server-deferred-timeout nil fail
                                     "The server did not answer in time" 504))))
      (setq later later-for-real))
    now))

;;;; For the studio: the data of a server that lives in a browser tab

;; The tab's server keeps its data directory in memory.  The studio saves
;; it in the browser after a request that changed it and gives it back to
;; the next server.

(defun app-server--data-files ()
  "The files of the data directory and of files/ in it (kept uploads).
Without SQLite's transient journals and uploads that are under way."
  (and (file-directory-p app-server-data-directory)
       (seq-filter (lambda (file) (and (file-regular-p file) (not (string-suffix-p "-journal" file))))
                   (append (directory-files app-server-data-directory t "\\`[^.]")
                           (let ((kept (expand-file-name "files/" app-server-data-directory)))
                             (and (file-directory-p kept) (directory-files kept t "\\`[^.]")))))))

(defun app-server--data-name (file)
  "FILE of the data directory as the studio names it: NAME or files/NAME."
  (file-relative-name file app-server-data-directory))

(defun app-server--signature ()
  "A string that changes when the data directory's files do."
  (mapconcat (lambda (file)
               (let ((attributes (file-attributes file)))
                 (format "%s:%d:%s" (app-server--data-name file)
                         (file-attribute-size attributes)
                         (format-time-string "%s%N" (file-attribute-modification-time attributes)))))
             (app-server--data-files) "|"))

(defun app-server--dump ()
  "The data directory: a vector of [FILE-NAME BASE64-CONTENT]."
  (vconcat
   (mapcar (lambda (file)
             (vector (app-server--data-name file)
                     (with-temp-buffer
                       (set-buffer-multibyte nil)
                       (insert-file-contents-literally file)
                       (base64-encode-string (buffer-string) t))))
           (app-server--data-files))))

(defun app-server--restore (entries)
  "Put back what `app-server--dump' returned."
  (make-directory app-server-data-directory t)
  (let ((coding-system-for-write 'no-conversion))
    (mapc (lambda (entry)
            (unless (string-match-p "\\`\\(?:files/\\)?[A-Za-z0-9_-][A-Za-z0-9_.-]*\\'" (aref entry 0))
              (error "Not a data file name: %S" (aref entry 0)))
            (make-directory (file-name-directory (expand-file-name (aref entry 0) app-server-data-directory)) t)
            (with-temp-file (expand-file-name (aref entry 0) app-server-data-directory)
              (set-buffer-multibyte nil)
              (insert (base64-decode-string (aref entry 1)))))
          entries))
  nil)

;;;; For the studio: waiting, in a server that lives in a browser tab

;; That Emacs runs only while it answers a call of the page; it has no
;; timers and no network of its own.  So the page waits for it: what
;; `app-server-after' and `app-server-fetch' ask for is collected here, the
;; page does it (setTimeout, fetch) and reports back, and deferred answers
;; that are complete are collected for the page to deliver.

(defvar app-server--tab-next 0)
(defvar app-server--tab-commands nil "Work for the page: (ID COMMAND ARGUMENT), newest first.")
(defvar app-server--tab-waiting (make-hash-table) "ID -> function (OK VALUE) for the page's report.")
(defvar app-server--tab-finished nil "Deferred answers that are ready: (ID STATUS TEXT), newest first.")

(defun app-server--tab-command (command argument function)
  (let ((id (cl-incf app-server--tab-next)))
    (puthash id function app-server--tab-waiting)
    (push (list id command argument) app-server--tab-commands)))

(defun app-server-use-tab-host ()
  "Let the page do the waiting (this Emacs lives in a browser tab)."
  (setq app-server--tab t
        ;; Passwords: the browser's Web Crypto does PBKDF2.  Should the page
        ;; have none, this Emacs does it itself, slowly.
        app-server-kdf-function
        (lambda (algorithm parameters password salt then)
          (app-server--tab-command
           "kdf" (list :algorithm algorithm :parameters parameters :password password :salt salt)
           (lambda (ok value)
             (funcall then (cond ((and ok (stringp value)) value)
                                 ((equal algorithm "pbkdf2-sha256")
                                  (app-server--pbkdf2 (encode-coding-string password 'utf-8) salt
                                                      (string-to-number parameters))))))))
        app-server-after-function
        (lambda (seconds function)
          (app-server--tab-command "timeout" (round (* 1000 seconds)) (lambda (_ok _value) (funcall function))))
        app-server-run-function
        (lambda (&rest _) (error "A server in a browser tab cannot run programs"))
        app-server-fetch-function
        (lambda (url method headers body then catch)
          (app-server--tab-command "fetch" (list :url url :method method :headers headers :body body)
                                   (lambda (ok value) (funcall (if ok then catch) value))))))

(defun app-server-tab-files (files removed)
  "Copy the project's FILES ([NAME TEXT] ...) here, delete REMOVED (names).
NAMEs are relative to `app-server-project-directory'.  A file that this
Emacs has loaded is loaded again.  Returns the names of those."
  (let ((loaded (app-server-project-files))
        (again nil)
        (coding-system-for-write 'utf-8-unix))
    (mapc (lambda (name)
            (ignore-errors (delete-file (app-server--project-file name))))
          removed)
    (mapc (lambda (entry)
            (let ((file (app-server--project-file (aref entry 0))))
              (make-directory (file-name-directory file) t)
              (write-region (aref entry 1) nil file nil 'silent)
              (when (member (aref entry 0) loaded) (push (aref entry 0) again))))
          files)
    (setq again (nreverse again))
    (dolist (name again) (load (app-server--project-file name) nil t t))
    (vconcat again)))

(defun app-server--project-file (name)
  "NAME, relative to the project, as a file name; not outside it."
  (let ((file (expand-file-name name app-server-project-directory)))
    (unless (string-prefix-p app-server-project-directory file)
      (error "Not a file of the project: %S" name))
    file))

(defun app-server--tab-events ()
  "What happened since the last call, for the page:
\(:commands [[ID COMMAND ARGUMENT] ...] :finished [[ID STATUS TEXT HEADERS] ...])."
  (prog1 (list :commands (vconcat (mapcar #'vconcat (nreverse app-server--tab-commands)))
               :finished (vconcat (mapcar #'vconcat (nreverse app-server--tab-finished))))
    (setq app-server--tab-commands nil app-server--tab-finished nil)))

(defun app-server--tab-headers (headers)
  "The response HEADERS, a list of (NAME . VALUE), as [[NAME VALUE] ...]."
  (vconcat (mapcar (lambda (header) (vector (car header) (cdr header))) headers)))

(defun app-server--tab-body (body)
  "BODY of an answer for the page: text, or a file as (:base64 ... :type ...)."
  (if (stringp body)
      body
    (list :base64 (with-temp-buffer
                    (set-buffer-multibyte nil)
                    (insert-file-contents-literally (plist-get body :file))
                    (base64-encode-string (buffer-string) t))
          :type (plist-get body :type) :name (plist-get body :name))))

(defun app-server-tab-request (method path body &optional headers upload)
  "Answer a request of the page's application.
HEADERS is a plist (:cookie \"...\" :content-type \"...\").  UPLOAD, when the
body is not text, is (:base64 STRING :type STRING).  The value is
\(:answer [STATUS BODY HEADERS]) or, when the answer comes later,
\(:pending ID); in both cases with the :commands and :finished of
`app-server--tab-events'.  In an answer, HEADERS is [[NAME VALUE] ...] and
BODY is text or (:base64 STRING :type STRING :name STRING) for a file."
  (let* ((id (cl-incf app-server--tab-next))
         (alist (cl-loop for (name value) on headers by #'cddr
                         collect (cons (downcase (substring (symbol-name name) 1)) value)))
         (bytes (and upload (base64-decode-string (plist-get upload :base64))))
         (accept (and bytes (app-server-upload-accept method path (length bytes) alist)))
         (file (and (eq accept t) (app-server-upload-file)))
         (done (lambda () (when file (ignore-errors (delete-file file)))))
         (answer
          (cond
           ((vectorp accept) accept)
           ;; Not a file for server.el: text, if it is not too much of it.
           ((and bytes (not accept) (> (length bytes) (* 1024 1024)))
            (vector 413 "Content Too Large" nil))
           (t
            (when file
              (let ((coding-system-for-write 'binary))
                (write-region bytes nil file nil 'silent)))
            (app-server-respond
             method path (cond (file "") (bytes (decode-coding-string bytes 'utf-8)) (t body))
             (lambda (status body headers)
               (push (list id status (app-server--tab-body body) (app-server--tab-headers headers))
                     app-server--tab-finished)
               (funcall done))
             alist
             (and file (list :file file :size (length bytes)
                             :type (or (plist-get upload :type) "application/octet-stream"))))))))
    (when answer (funcall done))
    (append (if answer
                (list :answer (vector (aref answer 0) (app-server--tab-body (aref answer 1))
                                      (app-server--tab-headers (aref answer 2))))
              (list :pending id))
            (app-server--tab-events))))

(defun app-server-tab-report (id ok value)
  "The page has done the command ID: OK and VALUE are its result.
Returns `app-server--tab-events'."
  (let ((function (gethash id app-server--tab-waiting)))
    (remhash id app-server--tab-waiting)
    (when function (funcall function ok value)))
  (app-server--tab-events))

(provide 'app-server)
;;; app-server.el ends here
