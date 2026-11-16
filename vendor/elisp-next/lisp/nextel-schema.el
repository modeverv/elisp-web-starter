;;; nextel-schema.el --- record types that the page and the server share  -*- lexical-binding: t; -*-

;; Copyright (c) 2026 modeverv
;; SPDX-License-Identifier: MIT
;; This file is part of elisp-next: https://github.com/modeverv/elisp-next

;; Both ends of the application are Emacs Lisp, so a record's definition
;; can be one file that both load (shared/): what the server sends and
;; what the page expects are the same definition, checked at both ends
;; when a value crosses.  There is no compiler that proves it, as
;; TypeScript would; there is a check that names the field that is wrong.
;;
;;   (nextel-defschema parens-video
;;     "A video, whichever source described it."
;;     (id string :required t)
;;     (title string)
;;     (views integer)
;;     (live (member live upcoming)))
;;
;; defines:
;;
;;   (make-parens-video :id "x" :title "y")   a record (a plist), checked
;;   (parens-video-title VIDEO)               a field
;;   (parens-video-p VALUE)                   whether VALUE is one
;;   (nextel-check 'parens-video VALUE)         VALUE, or a `nextel-type-error'
;;                                            that says which field is wrong
;;
;; A record is a plist, so it prints and reads as Lisp data and crosses
;; the network as it is.  A field may be left out (nil) unless it is
;; :required; a key that the schema does not name is an error.
;;
;; Types: string, integer, number, boolean (t or nil), symbol, keyword,
;; any, a schema's name, (member VALUE...), (list-of TYPE),
;; (vector-of TYPE), (or TYPE...).

;;; Code:

(require 'cl-lib)

(define-error 'nextel-type-error "Not of the expected type")

(defvar nextel--schemas (make-hash-table)
  "Schema name -> its fields: ((NAME TYPE :required BOOL) ...).")

(defun nextel-schema-fields (name)
  "The fields of the schema NAME, or nil if there is no such schema."
  (gethash name nextel--schemas))

(defmacro nextel-defschema (name &rest fields)
  "Define the record type NAME with FIELDS, each (FIELD TYPE [:required t]).
A string first is the documentation.  See the commentary of nextel-schema.el."
  (declare (indent 1) (doc-string 2))
  (let ((doc (and (stringp (car fields)) (pop fields))))
    (dolist (field fields)
      (unless (and (consp field) (symbolp (car field)) (cdr field))
        (error "nextel-defschema %s: a field is (NAME TYPE [:required t]), not %S" name field)))
    `(progn
       (puthash ',name ',(mapcar (lambda (field)
                                   (list (car field) (cadr field) :required (plist-get (cddr field) :required)))
                                 fields)
                nextel--schemas)
       (defun ,(intern (format "make-%s" name)) (&rest fields)
         ,(format "A `%s' record of FIELDS (a plist), checked.%s" name (if doc (concat "\n" doc) ""))
         (nextel-check ',name fields))
       (defun ,(intern (format "%s-p" name)) (value)
         ,(format "Non-nil if VALUE is a `%s' record." name)
         (nextel-type-p ',name value))
       ,@(mapcar (lambda (field)
                   `(defsubst ,(intern (format "%s-%s" name (car field))) (record)
                      ,(format "The field %s of the `%s' RECORD." (car field) name)
                      (plist-get record ,(intern (format ":%s" (car field))))))
                 fields)
       ',name)))

(defun nextel--type-name (type)
  (if (consp type) (format "%S" type) (symbol-name type)))

(defun nextel--fail (where type value)
  (signal 'nextel-type-error
          (list (format "%s: expected %s, got %s" where (nextel--type-name type)
                        (let ((print-length 4) (print-level 2)) (prin1-to-string value))))))

(defun nextel-check (type value &optional where)
  "VALUE if it is of TYPE; otherwise signal `nextel-type-error'.
WHERE names the value in the message (the type's name by default)."
  (let ((where (or where (nextel--type-name type))))
    (pcase type
      ('any value)
      ('string (if (stringp value) value (nextel--fail where type value)))
      ('integer (if (integerp value) value (nextel--fail where type value)))
      ('number (if (numberp value) value (nextel--fail where type value)))
      ('boolean (if (memq value '(nil t)) value (nextel--fail where type value)))
      ('symbol (if (symbolp value) value (nextel--fail where type value)))
      ('keyword (if (keywordp value) value (nextel--fail where type value)))
      (`(member . ,values) (if (member value values) value (nextel--fail where type value)))
      (`(list-of ,item)
       (unless (listp value) (nextel--fail where type value))
       (let ((index -1))
         (dolist (each value value)
           (nextel-check item each (format "%s[%d]" where (cl-incf index))))))
      (`(vector-of ,item)
       (unless (vectorp value) (nextel--fail where type value))
       (dotimes (index (length value))
         (nextel-check item (aref value index) (format "%s[%d]" where index)))
       value)
      (`(or . ,types)
       (if (cl-some (lambda (each) (nextel-type-p each value)) types) value (nextel--fail where type value)))
      ((pred symbolp)
       (let ((fields (or (nextel-schema-fields type) (error "No type or schema named %s" type))))
         (unless (and (listp value) (cl-evenp (length value)))
           (nextel--fail where type value))
         (cl-loop for key in value by #'cddr
                  do (unless (and (keywordp key) (assq (intern (substring (symbol-name key) 1)) fields))
                       (signal 'nextel-type-error (list (format "%s: no field %S in %s" where key type)))))
         (dolist (field fields value)
           (let* ((name (car field))
                  (field-value (plist-get value (intern (format ":%s" name))))
                  (field-where (format "%s.%s" where name)))
             (cond (field-value (nextel-check (cadr field) field-value field-where))
                   ((plist-get (cddr field) :required)
                    (signal 'nextel-type-error (list (format "%s is required" field-where)))))))))
      (_ (error "Not a type: %S" type)))))

(defun nextel-type-p (type value)
  "Non-nil if VALUE is of TYPE."
  (condition-case nil (progn (nextel-check type value) t) (nextel-type-error nil)))

(provide 'nextel-schema)
;;; nextel-schema.el ends here
