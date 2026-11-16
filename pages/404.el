;;; 404.el --- an address that no file of pages/ has  -*- lexical-binding: t; -*-

(nextel-page NotFoundPage
  :head (lambda (_route _data) (list :title "Not found"))
  :render (lambda (self)
            (jsx (div (:class "missing")
                   (h1 "Not found")
                   (p "Nothing is at " (code (plist-get (react-props self :route) :path)) ".")
                   (p (Link (:href (nextel-href "/")) "All notes"))))))

;;; 404.el ends here
