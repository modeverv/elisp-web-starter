;;; [id].el --- /notes/ID: one note, to read, change or delete  -*- lexical-binding: t; -*-

(nextel-page NotePage
  :load (lambda (route)
          (nextel-request "GET" "/api/notes/[id]" :id (nextel-param route :id) :returns 'starter-note))
  :head (lambda (_route note)
          (list :title (starter-note-title note) :description (starter-excerpt (starter-note-body note) 150)))
  :loading (lambda (_route) (jsx (p (:class "loading") "Loading the note…")))
  :error (lambda (_route error retry)
           (jsx (div (:class "failed")
                  (p (:role "alert") (plist-get error :message))
                  (p (button (:class "retry" :type "button" :on-click (lambda (_event) (funcall retry)))
                       "Try again")
                     " "
                     (Link (:href (nextel-href "/")) "All notes")))))
  :initial-state (lambda (_props) (list :editing nil :confirm nil :problem nil))
  :render
  (lambda (self)
    (let ((note (nextel-data self)))
      (jsx (article (:class (if (starter-note-done note) "note-page done" "note-page"))
             (if (react-state self :editing)
                 (jsx (NoteForm (:note note
                                 :label "Save"
                                 :save (lambda (draft)
                                         (nextel-request "PUT" "/api/notes/[id]" :id (starter-note-id note)
                                                         :body draft :sends 'starter-draft :returns 'starter-note))
                                 :on-saved (lambda (_note)
                                             (react-set-state self :editing nil)
                                             (nextel-reload))
                                 :on-cancel (lambda () (react-set-state self :editing nil)))))
               (starter-view self note))
             (and (react-state self :problem)
                  (jsx (p (:class "problem" :role "alert") (react-state self :problem))))
             (p (:class "back") (Link (:href (nextel-href "/")) "← All notes")))))))

(defun starter-view (self note)
  "NOTE to read, with its buttons, in the NotePage SELF."
  (let ((created (starter-note-created note))
        (updated (starter-note-updated note))
        (body (starter-note-body note)))
    (jsx (div (:class "view")
           (h1 (starter-note-title note))
           (p (:class "meta")
              (if (starter-note-done note) "Done · " "")
              "Written " (starter-date created)
              (if (equal created updated) "" (concat " · changed " (starter-date updated))))
           (if (and body (not (string-empty-p body)))
               (jsx (div (:class "text") body))
             (jsx (p (:class "text empty") "No text.")))
           (div (:class "actions")
             (button (:class "edit" :type "button"
                      :on-click (lambda (_event) (react-set-state self :editing t :confirm nil)))
               "Edit")
             (if (react-state self :confirm)
                 (jsx (span (:class "confirm")
                        "Delete this note? "
                        (button (:class "really-delete danger" :type "button"
                                 :on-click (lambda (_event) (starter-delete-note-page self note)))
                          "Delete")
                        (button (:class "keep" :type "button"
                                 :on-click (lambda (_event) (react-set-state self :confirm nil)))
                          "Keep")))
               (jsx (button (:class "delete" :type "button"
                             :on-click (lambda (_event) (react-set-state self :confirm t)))
                      "Delete"))))))))

(defun starter-delete-note-page (self note)
  "Delete NOTE on the server, then go to the list; a failure shows in SELF."
  (react-async
    (condition-case failure
        (progn
          (react-await (nextel-request "DELETE" "/api/notes/[id]" :id (starter-note-id note)
                                       :returns 'starter-note))
          (nextel-go "/")
          (nextel-reload))
      (react-async-error
       (react-set-state self :confirm nil :problem (plist-get (cadr failure) :message))))))

;;; [id].el ends here
