#!/bin/sh
# SPDX-License-Identifier: 0BSD  (yours to change; no conditions)
# Run on the host by deploy.sh: put the project that came in INCOMING (a
# directory of the home directory) in place.
#   install.sh INCOMING WEB-DIR APP-DIR PUBLIC-ORIGIN
set -eu
cd "$HOME"
incoming="$HOME/$1"; web="$HOME/$2"; app="$HOME/$3"; origin="$4"
trap 'rm -rf "$incoming"' EXIT
emacs="$(command -v emacs || true)"
[ -n "$emacs" ] || { echo "install.sh: no emacs on the host" >&2; exit 1; }
"$emacs" --batch -Q --eval '(unless (version<= "27.2" emacs-version) (kill-emacs 1))' \
  || { echo "install.sh: the host's Emacs is older than 27.2" >&2; exit 1; }
umask 022
mkdir -p "$app" "$web" "$app/data"
# The whole project to APP-DIR (outside the web root), over what was there;
# the data directory and my.cnf stay.
( cd "$incoming" && tar -cf - . ) | ( cd "$app" && tar -xf - )
# After the copy: GNU tar gives APP-DIR the mode of INCOMING's '.'.
chmod 700 "$app" "$app/data"
# The page's files to WEB-DIR: not the server's, and no hidden files
# ('./.*' would be './' itself to bsdtar, and nothing would go).
( cd "$incoming" && tar -cf - --exclude './.?*' --exclude ./server --exclude ./server.el --exclude ./api --exclude ./test \
    --exclude ./.github --exclude './*.sh' --exclude ./Dockerfile --exclude ./docker-compose.yml \
    --exclude ./.dockerignore --exclude ./README.txt . ) | ( cd "$web" && tar -xf - )
[ -f "$web/index.html" ] || { echo "install.sh: the page's files did not reach $web" >&2; exit 1; }
cp "$app/server/cgi/htaccess" "$web/.htaccess"
mysql=""; [ -f "$app/my.cnf" ] && mysql="$app/my.cnf"
cat > "$web/app.cgi" <<CGI
#!/bin/sh
# Written by server/cgi/install.sh.  Each request to /api/ starts an Emacs,
# which answers it with server.el and ends.  What it reads is outside the
# web root, in $app.
APP_DIRECTORY=$app
APP_DATA=$app/data
APP_MYSQL=$mysql
PUBLIC_ORIGIN=$origin
PATH="$PATH"
export APP_DIRECTORY APP_DATA APP_MYSQL PUBLIC_ORIGIN PATH
exec $emacs --batch -Q -l "\$APP_DIRECTORY/server/serve-cgi.el" -f serve-cgi-main
CGI
chmod 755 "$web/app.cgi"
# The jobs of server.el, for cron: APP-DIR/job.sh [NAME].
cat > "$app/job.sh" <<JOB
#!/bin/sh
# Written by server/cgi/install.sh.  Runs the jobs of server.el that are
# due (app-server-defjob), or the one named, in an Emacs that then ends;
# one line per job in $app/data/jobs.log.  For cron: $app/job.sh
APP_DIRECTORY=$app
APP_DATA=$app/data
APP_MYSQL=$mysql
PUBLIC_ORIGIN=$origin
APP_JOB=\${1:-}
# The PATH of the deployment: cron's has neither curl nor mysql on some hosts.
PATH="$PATH"
export APP_DIRECTORY APP_DATA APP_MYSQL PUBLIC_ORIGIN APP_JOB PATH
exec $emacs --batch -Q -l "\$APP_DIRECTORY/server/serve-cgi.el" -f serve-cgi-jobs-main
JOB
chmod 700 "$app/job.sh"
# Compiled, the server's Lisp loads in a fraction of the time: each request pays it.
( cd "$app/server" && rm -f ./*.elc && "$emacs" --batch -Q -L . --eval '(setq byte-compile-warnings nil)' \
    -f batch-byte-compile app-server.el serve-project.el serve-cgi.el >/dev/null 2>&1 )
# elisp-next, its shared/ and api/ too, when the project has it: compiled the
# same way, with what they use loaded; a file that does not compile is
# loaded as it is.  Old .elc files go first (tar keeps the dates of the
# sources, which may be older than they).
if [ -f "$app/vendor/elisp-next/lisp/nextel-server.el" ]; then
  ( cd "$app" && find shared api vendor/elisp-next/lisp -name '*.elc' -exec rm -f {} + 2>/dev/null || true
    ( cd vendor/elisp-next/lisp && "$emacs" --batch -Q -L . --eval '(setq byte-compile-warnings nil)' \
        -f batch-byte-compile nextel-schema.el nextel-route.el nextel-server.el >/dev/null 2>&1 || true )
    "$emacs" --batch -Q --eval '(setq byte-compile-warnings nil load-prefer-newer t)' \
      -l "$app/server/app-server.elc" -l "$app/vendor/elisp-next/lisp/nextel-server.el" \
      --eval '(let ((app-server-project-directory default-directory) (nextel-server-lazy t))
                (nextel-server-load)
                (dolist (directory (quote ("shared" "api")))
                  (when (file-directory-p directory)
                    (dolist (file (directory-files-recursively directory "\\`[^.].*\\.el\\'"'"'"))
                      (unless (string-match-p "/\\." file) (ignore-errors (byte-compile-file file)))))))' >/dev/null 2>&1 || true )
fi
echo "install.sh: $origin/ is $web; the server reads $app$( [ -n "$mysql" ] && echo ", data in MySQL" || true ); jobs: $app/job.sh"
