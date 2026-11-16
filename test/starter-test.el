;;; starter-test.el --- the application in one native Emacs: the server and the pages  -*- lexical-binding: t; -*-

;; test/run.sh runs it:
;;
;;   emacs --batch -Q -l test/starter-test.el -f ert-run-tests-batch-and-exit
;;
;; Everything it uses is in the project (server/app-server.el, vendor/): no
;; network, no browser.  The server answers as it does under run.sh (SQLite,
;; in a temporary directory).  react-testing.el (elisp-react) plays the
;; page: the scripts of index.html are loaded in their order, and each
;; request of the page is answered by the server, so a request goes the
;; whole way and its types are checked at both ends.
;;
;; Both sides share this one Emacs: a function name must not be defined by
;; the page and by the server differently.

(require 'ert)
(require 'cl-lib)
(require 'seq)

(defconst starter-test-root
  (file-name-directory (directory-file-name (file-name-directory (or load-file-name buffer-file-name))))
  "The project.")

(add-to-list 'load-path (expand-file-name "vendor/elisp-react/lisp" starter-test-root))
(add-to-list 'load-path (expand-file-name "vendor/elisp-next/lisp" starter-test-root))
(require 'react-testing)

;;;; The server: app-server.el, then server.el, as serve-project.el does

(load (expand-file-name "server/app-server.el" starter-test-root) nil t)
(setq app-server-data-directory (file-name-as-directory (make-temp-file "starter-data-" t)))
(app-server-use-project starter-test-root)
(load (expand-file-name "server.el" starter-test-root) nil t)

(defun starter-test-call (method path &optional body)
  "(STATUS DATA): the server's answer to METHOD PATH with BODY (text), read."
  (let ((answer (app-server-respond method path (or body "") nil)))
    (list (aref answer 0) (car (read-from-string (aref answer 1))))))

(defun starter-test-empty ()
  "No notes."
  (starter-sql #'app-server-sql-execute "DELETE FROM starter_notes"))

;;;; The page: the scripts of index.html in their order, as elisp-react.js loads them

(defun starter-test-scripts ()
  (with-temp-buffer
    (insert-file-contents (expand-file-name "index.html" starter-test-root))
    (let (scripts)
      (while (re-search-forward "<script type=\"text/emacs-lisp\" src=\"\\([^\"]+\\)\"" nil t)
        (push (match-string 1) scripts))
      (nreverse scripts))))

(defvar starter-test-followed 0 "How many of Lisp's navigations the page has followed.")

(defun starter-test-start (href)
  "Load the page at HREF (\"#/notes/1\")."
  (react-testing-reset)
  (setq starter-test-followed 0)
  (react-testing-location href)
  (dolist (script (starter-test-scripts))
    (load (expand-file-name script starter-test-root) nil t))
  (react-testing-flush))

(defun starter-test-told (command)
  "The arguments of what Lisp told the page to do with COMMAND, oldest first."
  (mapcar #'cadr (cl-remove-if-not (lambda (told) (equal (car told) command)) react-testing-told)))

(defun starter-test-follow ()
  "Go where Lisp navigated (`nextel-go'), as the browser would."
  (let ((navigations (starter-test-told "navigate")))
    (while (< starter-test-followed (length navigations))
      (let ((url (plist-get (nth starter-test-followed navigations) :url)))
        (setq starter-test-followed (1+ starter-test-followed))
        (react-testing-location url)))))

(defun starter-test-serve ()
  "Answer every request that the page waits for with the server's answer."
  (let (request)
    (starter-test-follow)
    (while (setq request (cl-find "fetch" react-testing-requests :key #'cadr :test #'equal))
      (let* ((argument (nth 2 request))
             (answer (app-server-respond (plist-get argument :method) (concat "/" (plist-get argument :url))
                                         (or (plist-get argument :body) "") nil)))
        (react-testing-answer-fetch (aref answer 0) (aref answer 1)))
      (starter-test-follow))))

(defun starter-test-title ()
  "The document's title now."
  (plist-get (car (last (starter-test-told "title"))) :text))

(defun starter-test-texts (class)
  "The texts of the elements of CLASS, in order."
  (mapcar #'react-testing-text (react-testing-find-all :class class)))

(defun starter-test-type (class value)
  "Type VALUE into the field of CLASS."
  (react-testing-input (react-testing-find :class class) value))

;;;; The server alone

(ert-deftest starter-api ()
  (starter-test-empty)
  (should (equal (starter-test-call "GET" "/api/notes") '(200 nil)))
  ;; A new note: the title is trimmed, the text kept, the times set.
  (pcase-let ((`(,status ,note) (starter-test-call "POST" "/api/notes" "(:title \" Milk \" :body \"2 litres\")")))
    (should (equal status 200))
    (should (starter-note-p note))
    (should (equal (starter-note-title note) "Milk"))
    (should (equal (starter-note-body note) "2 litres"))
    (should (integerp (starter-note-created note))))
  (should (equal (car (starter-test-call "POST" "/api/notes" "(:title \"Bread\")")) 200))
  (should (equal (car (starter-test-call "POST" "/api/notes" "(:title \"100% juice\")")) 200))
  ;; What :accepts refuses (the type), and what the shared check refuses.
  (should (equal (starter-test-call "POST" "/api/notes" "(:title 3)") '(400 "body.title: expected string, got 3")))
  (should (equal (starter-test-call "POST" "/api/notes" "") '(400 "body.title is required")))
  (should (equal (starter-test-call "POST" "/api/notes" "(:title \"x\" :id \"7\")")
                 '(400 "body: no field :id in starter-draft")))
  ;; A keyword that no schema has is refused before the type is looked at
  ;; (it is never read into the server's Emacs: elisp-next's pitfall 19).
  (should (equal (starter-test-call "POST" "/api/notes" "(:title \"x\" :colour \"red\")")
                 '(400 "The request names something unknown: :colour")))
  (should (equal (starter-test-call "POST" "/api/notes" "(:title \"   \")") '(400 "A note needs a title")))
  (should (equal (starter-test-call "POST" "/api/notes" (format "(:title %S)" (make-string 201 ?x)))
                 '(400 "A title has at most 200 characters")))
  ;; The list, the last changed first; a search, whose % and _ are plain.
  (should (equal (mapcar #'starter-note-title (cadr (starter-test-call "GET" "/api/notes")))
                 '("100% juice" "Bread" "Milk")))
  (should (equal (mapcar #'starter-note-title (cadr (starter-test-call "GET" "/api/notes?q=milk"))) '("Milk")))
  (should (equal (mapcar #'starter-note-title (cadr (starter-test-call "GET" "/api/notes?q=%25"))) '("100% juice")))
  (should (equal (starter-test-call "GET" "/api/notes?q=_") '(200 nil)))
  ;; One note: found, changed, deleted.
  (let ((id (starter-note-id (car (cadr (starter-test-call "GET" "/api/notes?q=Milk"))))))
    (should (equal (starter-note-title (cadr (starter-test-call "GET" (concat "/api/notes/" id)))) "Milk"))
    (pcase-let ((`(,status ,note) (starter-test-call "PUT" (concat "/api/notes/" id) "(:title \"Oat milk\" :done t)")))
      (should (equal status 200))
      (should (equal (starter-note-title note) "Oat milk"))
      (should (equal (starter-note-body note) ""))
      (should (eq (starter-note-done note) t)))
    (should (equal (starter-test-call "PUT" (concat "/api/notes/" id) "(:title \"\")") '(400 "A note needs a title")))
    (should (equal (starter-note-title (cadr (starter-test-call "DELETE" (concat "/api/notes/" id)))) "Oat milk"))
    (should (equal (starter-test-call "DELETE" (concat "/api/notes/" id)) '(404 "No such note")))
    (should (equal (starter-test-call "GET" (concat "/api/notes/" id)) '(404 "No such note"))))
  (should (equal (starter-test-call "GET" "/api/notes/abc") '(404 "No such note")))
  (should (equal (starter-test-call "PUT" "/api/notes/999" "(:title \"x\")") '(404 "No such note")))
  ;; No such method, no such route.
  (should (equal (starter-test-call "PATCH" "/api/notes") '(405 "PATCH is not allowed at /api/notes")))
  (should (equal (starter-test-call "GET" "/api/nothing") '(404 "No such API: /api/nothing")))
  ;; Health: the database answers, VERSIONS is read.
  (let ((health (cadr (starter-test-call "GET" "/api/health"))))
    (should (starter-health-p health))
    (should (equal (starter-health-status health) "ok"))
    (should (equal (starter-health-database health) "sqlite"))
    (should (equal (starter-health-notes health) 2))
    (should (seq-find (lambda (line) (string-prefix-p "ELISP_NEXT=" line)) (starter-health-versions health)))))

;;;; The pages, with the server behind them

(ert-deftest starter-pages-notes ()
  (starter-test-empty)
  (starter-test-start "#/")
  (starter-test-serve)
  (should (equal (starter-test-texts "empty") '("No notes yet: write the first one.")))
  (should (equal (starter-test-title) "Notes"))
  ;; Write one: the form sends it, the list loads again, the form is empty.
  (starter-test-type "title" "Milk")
  (starter-test-type "body" "2 litres\nskimmed")
  (react-testing-submit (react-testing-find :class "note-form"))
  (starter-test-serve)
  (should (equal (starter-test-texts "title") '("" "Milk")))   ; the form's field, then the note's link
  (should (equal (starter-test-texts "excerpt") '("2 litres")))
  (should (equal (react-testing-property (react-testing-find :tag 'input :class "title") "value") ""))
  ;; A note without a title is not sent: the shared check says why.
  (react-testing-submit (react-testing-find :class "note-form"))
  (should-not react-testing-requests)
  (should (equal (starter-test-texts "problem") '("A note needs a title")))
  ;; Done, from the list.
  (react-testing-dispatch (react-testing-find :class "toggle") "change" '(:checked t))
  (starter-test-serve)
  (should (react-testing-find :class "done"))
  ;; Its page: loading, then the note, its title in the document's.
  (let ((href (react-testing-attribute (react-testing-find :tag 'a :text "Milk") "href")))
    (should (string-match-p "\\`#/notes/[0-9]+\\'" href))
    (react-testing-location href))
  (should (equal (starter-test-texts "loading") '("Loading the note…")))
  (starter-test-serve)
  (should (equal (react-testing-text (react-testing-find :tag 'h1)) "Milk"))
  (should (string-prefix-p "Done · Written " (car (starter-test-texts "meta"))))
  (should (equal (starter-test-title) "Milk · Notes"))
  ;; Change it.
  (react-testing-click (react-testing-find :class "edit"))
  (should (equal (react-testing-property (react-testing-find :tag 'input :class "title") "value") "Milk"))
  (starter-test-type "title" "Oat milk")
  (react-testing-dispatch (react-testing-find :class "mark-done") "change" '(:checked nil))
  (react-testing-submit (react-testing-find :class "note-form"))
  (starter-test-serve)
  (should (equal (react-testing-text (react-testing-find :tag 'h1)) "Oat milk"))
  (should (string-prefix-p "Written " (car (starter-test-texts "meta"))))
  ;; Delete it: asked once more, then gone, and the list is shown.
  (react-testing-click (react-testing-find :class "delete"))
  (should (react-testing-find :class "confirm"))
  (react-testing-click (react-testing-find :class "really-delete"))
  (starter-test-serve)
  (should (equal (starter-test-texts "empty") '("No notes yet: write the first one.")))
  ;; Its address now: the server's 404 reaches the page's :error.
  (react-testing-location "#/notes/1")
  (starter-test-serve)
  (should (equal (react-testing-text (react-testing-find :class "failed")) "No such noteTry again All notes")))

(ert-deftest starter-pages-refused ()
  ;; A note deleted elsewhere while it is being changed: the server's
  ;; refusal shows in the form.
  (starter-test-empty)
  (let ((id (starter-note-id (cadr (starter-test-call "POST" "/api/notes" "(:title \"Tea\")")))))
    (starter-test-start (concat "#/notes/" id))
    (starter-test-serve)
    (react-testing-click (react-testing-find :class "edit"))
    (starter-test-call "DELETE" (concat "/api/notes/" id))
    (react-testing-submit (react-testing-find :class "note-form"))
    (starter-test-serve)
    (should (equal (starter-test-texts "problem") '("No such note")))))

(ert-deftest starter-pages-search-about-404 ()
  (starter-test-empty)
  (starter-test-call "POST" "/api/notes" "(:title \"Milk\")")
  (starter-test-call "POST" "/api/notes" "(:title \"Bread\" :body \"rye\")")
  ;; A search from the field goes to its own address (Back works, links can be shared).
  (starter-test-start "#/")
  (starter-test-serve)
  (should (equal (cdr (starter-test-texts "title")) '("Bread" "Milk")))
  (starter-test-type "q" "RYE")
  (react-testing-submit (react-testing-find :class "search"))
  (starter-test-serve)
  (should (equal (cdr (starter-test-texts "title")) '("Bread")))
  (should (equal (starter-test-title) "Search: RYE · Notes"))
  (should (react-testing-find :class "clear"))
  (react-testing-location "#/?q=nothing")
  (starter-test-serve)
  (should (equal (starter-test-texts "empty") '("No note has “nothing” in it.")))
  ;; The about page: both Emacsen, the database, VERSIONS.
  (react-testing-location "#/about")
  (starter-test-serve)
  (should (equal (starter-test-texts "server-emacs") (list (concat "GNU Emacs " emacs-version))))
  (should (equal (starter-test-texts "database") '("sqlite")))
  (should (equal (starter-test-texts "count") '("2")))
  (should (= (length (react-testing-find-all :tag 'code)) 5))
  ;; An address that no file of pages/ has.
  (react-testing-location "#/nowhere")
  (should (equal (react-testing-text (react-testing-find :class "missing"))
                 "Not foundNothing is at /nowhere.All notes"))
  (should (equal (starter-test-title) "Not found · Notes")))

;;; starter-test.el ends here
