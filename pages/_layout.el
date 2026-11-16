;;; _layout.el --- around every page  -*- lexical-binding: t; -*-

;; The header, the footer, and the document's title for every page:
;; "TITLE · Notes", or "Notes" for a page whose :head gives none.

(defconst starter-name "Notes" "The application's name.")

(setq nextel-title-function (lambda (title) (if title (concat title " · " starter-name) starter-name)))

(nextel-layout Layout
  :render
  (lambda (self)
    (jsx (div (:class "layout")
           (header (:class "top")
             (Link (:href (nextel-href "/") :class "brand") starter-name)
             (nav (Link (:href (nextel-href "/") :class "nav-notes") "Notes")
                  (Link (:href (nextel-href "/about") :class "nav-about") "About")))
           (main (react-props self :children))
           (footer (:class "bottom")
             "Emacs Lisp on both sides: "
             (a (:href "https://github.com/modeverv/elisp-web-starter") "elisp-web-starter"))))))

;;; _layout.el ends here
