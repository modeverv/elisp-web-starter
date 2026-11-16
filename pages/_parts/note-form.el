;;; note-form.el --- the form that writes a note: new, or changed  -*- lexical-binding: t; -*-

;; (NoteForm (:label "Add note" :save FUNCTION :on-saved FUNCTION))
;; (NoteForm (:note NOTE :label "Save" :save FUNCTION :on-saved FUNCTION :on-cancel FUNCTION))
;;
;; :save is a function of a starter-draft that returns the request
;; (`nextel-request'); :on-saved gets the note the server answered.  The
;; draft is checked here first, with the same `starter-check-draft' as the
;; server's: a wrong one is not sent.  A refusal of the server shows in
;; the form as well.

(require 'subr-x)

(defun starter-form-draft (self)
  "The draft that the NoteForm SELF would send."
  (list :title (string-trim (react-state self :title))
        :body (react-state self :body)
        :done (react-state self :done)))

(defun starter-save-form (self)
  "Send the draft of the NoteForm SELF, unless something is wrong with it."
  (let* ((draft (starter-form-draft self))
         (problem (starter-check-draft draft)))
    (if problem
        (react-set-state self :problem problem)
      (react-set-state self :problem nil :busy t)
      (react-async
        (condition-case failure
            (let ((note (react-await (funcall (react-props self :save) draft))))
              ;; A new note's form is empty again; a changed note's keeps it.
              (if (react-props self :note)
                  (react-set-state self :busy nil)
                (react-set-state self :busy nil :title "" :body ""))
              (funcall (react-props self :on-saved) note))
          ;; :sends refused it: nothing was sent.
          (nextel-type-error (react-set-state self :busy nil :problem (cadr failure)))
          ;; The server refused it, or its answer was not a starter-note.
          (react-async-error
           (react-set-state self :busy nil :problem (plist-get (cadr failure) :message))))))))

(react-define-component 'NoteForm
  :initial-state
  (lambda (props)
    (let ((note (plist-get props :note)))
      (list :title (if note (starter-note-title note) "")
            :body (or (and note (starter-note-body note)) "")
            :done (and note (starter-note-done note))
            :problem nil
            :busy nil)))
  :render
  (lambda (self)
    (jsx (form (:class "note-form" :on-submit (lambda (_event) (starter-save-form self)))
           (label (:class "field")
             (span "Title")
             (input (:class "title" :name "title" :autocomplete "off" :value (react-state self :title)
                     :on-input (lambda (event) (react-set-state self :title (plist-get event :value))))))
           (label (:class "field")
             (span "Text")
             (textarea (:class "body" :name "body" :rows 5 :value (react-state self :body)
                        :on-input (lambda (event) (react-set-state self :body (plist-get event :value))))))
           (and (react-props self :note)
                (jsx (label (:class "check")
                       (input (:class "mark-done" :type "checkbox" :checked (react-state self :done)
                               :on-change (lambda (event) (react-set-state self :done (plist-get event :checked)))))
                       (span "Done"))))
           (and (react-state self :problem)
                (jsx (p (:class "problem" :role "alert") (react-state self :problem))))
           (div (:class "actions")
             (button (:class "save" :type "submit" :disabled (react-state self :busy))
               (react-props self :label))
             (and (react-props self :on-cancel)
                  (jsx (button (:class "cancel" :type "button"
                                :on-click (lambda (_event) (funcall (react-props self :on-cancel))))
                         "Cancel"))))))))

;;; note-form.el ends here
