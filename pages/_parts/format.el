;;; format.el --- dates and excerpts, for the pages  -*- lexical-binding: t; -*-

;; A helper of pages/ (in a directory whose name starts with _): the page
;; loads it after _layout.el, before the pages; it is no address.

(require 'subr-x)

(defun starter-date (seconds)
  "SECONDS since 1970 as a date and time of the visitor's time zone."
  ;; The page's Emacs runs in UTC; the browser knows the visitor's offset.
  (format-time-string "%Y-%m-%d %H:%M" seconds (* 60 (or (react-locale :offset) 0))))

(defun starter-excerpt (text &optional limit)
  "The first line of TEXT, at most LIMIT (80) characters of it."
  (let ((line (string-trim (car (split-string (or text "") "\n"))))
        (limit (or limit 80)))
    (if (> (length line) limit) (concat (substring line 0 (1- limit)) "…") line)))

;;; format.el ends here
