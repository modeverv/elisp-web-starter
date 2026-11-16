;;; index.el --- /: the notes, a search, and a form for a new one  -*- lexical-binding: t; -*-

(nextel-page HomePage
  :load (lambda (route)
          (nextel-request "GET" "/api/notes" :q (nextel-query route "q") :returns '(list-of starter-note)))
  :head (lambda (route notes)
          (list :title (let ((query (nextel-query route "q"))) (and query (format "Search: %s" query)))
                :description (format "%d notes" (length notes))))
  :initial-state (lambda (props) (list :search (or (nextel-query (plist-get props :route) "q") "") :problem nil))
  :render
  (lambda (self)
    (let ((notes (nextel-data self))
          (query (nextel-query self "q")))
      (jsx (div (:class "home")
             (section (:class "new")
               (h2 "New note")
               (NoteForm (:label "Add note"
                          :save (lambda (draft)
                                  (nextel-request "POST" "/api/notes" :body draft
                                                  :sends 'starter-draft :returns 'starter-note))
                          ;; The list (and every page seen) loads again.
                          :on-saved (lambda (_note) (nextel-reload)))))
             (section (:class "list")
               (form (:class "search" :role "search" :on-submit (lambda (_event) (starter-search self)))
                 (input (:class "q" :name "q" :type "search" :placeholder "Search notes"
                         :value (react-state self :search)
                         :on-input (lambda (event) (react-set-state self :search (plist-get event :value)))))
                 (button (:type "submit") "Search")
                 (and query (jsx (Link (:href (nextel-href "/") :class "clear") "Show all"))))
               (and (react-state self :problem)
                    (jsx (p (:class "problem" :role "alert") (react-state self :problem))))
               (if notes
                   (jsx (ul (:class "notes")
                          (mapcar (lambda (note) (starter-line self note)) notes)))
                 (jsx (p (:class "empty")
                        (if query
                            (format "No note has “%s” in it." query)
                          "No notes yet: write the first one."))))))))))

(defun starter-line (self note)
  "NOTE as a line of the list of the HomePage SELF."
  (let ((id (starter-note-id note))
        (done (starter-note-done note)))
    (jsx (li (:key id :class (if done "note done" "note"))
           (input (:class "toggle" :type "checkbox" :checked done :aria-label "Done"
                   :on-change (lambda (_event) (starter-toggle-note self note))))
           (div (:class "summary")
             (Link (:href (nextel-href "/notes/[id]" :id id) :class "title") (starter-note-title note))
             (p (:class "excerpt") (starter-excerpt (starter-note-body note)))
             (p (:class "meta") "Changed " (starter-date (starter-note-updated note))))))))

(defun starter-search (self)
  "Show the notes that have the search text of the HomePage SELF in them."
  (let ((text (string-trim (react-state self :search))))
    (if (string-empty-p text) (nextel-go "/") (nextel-go "/" :q text))))

(defun starter-toggle-note (self note)
  "Mark NOTE done, or not done, on the server; a failure shows in SELF."
  (react-set-state self :problem nil)
  (react-async
    (condition-case failure
        (progn
          (react-await (nextel-request "PUT" "/api/notes/[id]" :id (starter-note-id note)
                                       :body (list :title (starter-note-title note)
                                                   :body (or (starter-note-body note) "")
                                                   :done (not (starter-note-done note)))
                                       :sends 'starter-draft :returns 'starter-note))
          (nextel-reload))
      (react-async-error (react-set-state self :problem (plist-get (cadr failure) :message))))))

;;; index.el ends here
