;;; nextel-route.el --- addresses as file names: patterns, both ends  -*- lexical-binding: t; -*-

;; Copyright (c) 2026 modeverv
;; SPDX-License-Identifier: MIT
;; This file is part of elisp-next: https://github.com/modeverv/elisp-next

;; A route's pattern is the path of its file without the directory and
;; ".el": pages/channel/[id].el is "/channel/[id]", api/videos/[id].el is
;; "/api/videos/[id]".  A segment in brackets is a parameter; [...rest]
;; takes the rest of the path (one segment at least); index.el is its
;; directory.  The page (nextel.el) and the server (nextel-server.el) match
;; addresses against patterns with the same functions, here.

;;; Code:

(require 'cl-lib)
(require 'subr-x)
(require 'url-util)

(defun nextel--decode (text)
  "TEXT, a part of an address, with its escapes read as UTF-8."
  (decode-coding-string (url-unhex-string text) 'utf-8))

(defun nextel-pattern-of-file (file)
  "The pattern of FILE, a path relative to pages/ or to the project for api/.
\"watch.el\" -> \"/watch\", \"channel/[id].el\" -> \"/channel/[id]\",
\"index.el\" -> \"/\", \"api/feed/index.el\" -> \"/api/feed\"."
  (let ((parts (split-string (string-remove-suffix ".el" file) "/" t)))
    (when (equal (car (last parts)) "index") (setq parts (butlast parts)))
    (concat "/" (mapconcat #'identity parts "/"))))

(defun nextel-match (pattern path)
  "Whether PATH matches PATTERN: its parameters (a plist), t when it
matches a pattern without any, or nil.
  (nextel-match \"/channel/[id]\" \"/channel/UCx\")  =>  (:id \"UCx\")"
  (let ((want (split-string pattern "/" t))
        (have (split-string path "/" t))
        (params nil)
        (ok t))
    (while (and ok want)
      (let ((segment (pop want)))
        (cond ((string-match "\\`\\[\\.\\.\\.\\(.+\\)\\]\\'" segment)
               (if (or want (null have))
                   (setq ok nil)
                 (setq params (append params (list (intern (concat ":" (match-string 1 segment)))
                                                   (mapcar #'nextel--decode have)))
                       have nil)))
              ((string-match "\\`\\[\\(.+\\)\\]\\'" segment)
               (if (null have)
                   (setq ok nil)
                 (setq params (append params (list (intern (concat ":" (match-string 1 segment)))
                                                   (nextel--decode (pop have)))))))
              ((and have (equal segment (nextel--decode (car have)))) (pop have))
              (t (setq ok nil)))))
    (and ok (null have) (or params t))))

(defun nextel-pattern-rank (pattern)
  "A key that sorts PATTERN before the patterns it should be tried before:
fixed segments before parameters, parameters before [...rest]."
  (mapcar (lambda (segment)
            (cond ((string-prefix-p "[..." segment) 2)
                  ((string-prefix-p "[" segment) 1)
                  (t 0)))
          (split-string pattern "/" t)))

(defun nextel-pattern< (a b)
  "Non-nil if the pattern A is to be tried before B."
  (let ((ra (nextel-pattern-rank a)) (rb (nextel-pattern-rank b)))
    (while (and ra rb (= (car ra) (car rb)))
      (setq ra (cdr ra) rb (cdr rb)))
    (cond ((and ra rb) (< (car ra) (car rb)))
          ;; Of two that agree as far as both go, the longer first; of two
          ;; alike, the one first in the alphabet (any order is right, one
          ;; order is written the same everywhere).
          ((or ra rb) (and ra t))
          (t (string< a b)))))

(defun nextel--value-text (value)
  (cond ((stringp value) value)
        ((numberp value) (number-to-string value))
        ((symbolp value) (symbol-name value))
        (t (format "%s" value))))

(defun nextel-fill (pattern params)
  "PATTERN with its [names] taken from PARAMS (a plist), and a query of
the PARAMS left over (nil values left out): a string.
  (nextel-fill \"/channel/[id]\" \\='(:id \"UCx\"))      =>  \"/channel/UCx\"
  (nextel-fill \"/watch\" \\='(:v \"abc\" :t 30))        =>  \"/watch?v=abc&t=30\""
  (let* ((used nil)
         (path (mapconcat
                (lambda (segment)
                  (if (string-match "\\`\\[\\(?:\\.\\.\\.\\)?\\(.+\\)\\]\\'" segment)
                      (let* ((key (intern (concat ":" (match-string 1 segment))))
                             (value (plist-get params key)))
                        (push key used)
                        (unless value (error "%s needs %s" pattern key))
                        (if (listp value)
                            (mapconcat (lambda (part) (url-hexify-string (nextel--value-text part))) value "/")
                          (url-hexify-string (nextel--value-text value))))
                    segment))
                (split-string pattern "/" t) "/"))
         (query nil))
    (cl-loop for (key value) on params by #'cddr
             do (when (and value (not (memq key used)))
                  (push (concat (url-hexify-string (substring (symbol-name key) 1)) "="
                                (url-hexify-string (nextel--value-text value)))
                        query)))
    (concat "/" path (if query (concat "?" (mapconcat #'identity (nreverse query) "&")) ""))))

(provide 'nextel-route)
;;; nextel-route.el ends here
