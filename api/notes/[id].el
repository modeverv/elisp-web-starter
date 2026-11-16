;;; [id].el --- GET, PUT and DELETE /api/notes/ID  -*- lexical-binding: t; -*-

;; GET     the note
;; PUT     replace its title, text and done with a starter-draft; the note
;; DELETE  delete it; the note as it was
;;
;; A note that is not there is 404 for all three.

(nextel-handle "GET"
  :returns 'starter-note
  :handler (lambda (request)
             (or (starter-find-note (starter-request-id request)) (starter-no-note))))

(nextel-handle "PUT"
  :accepts 'starter-draft
  :returns 'starter-note
  :handler (lambda (request)
             (or (starter-change-note (starter-request-id request) (plist-get request :body))
                 (starter-no-note))))

(nextel-handle "DELETE"
  :returns 'starter-note
  :handler (lambda (request)
             (or (starter-delete-note (starter-request-id request)) (starter-no-note))))

;;; [id].el ends here
