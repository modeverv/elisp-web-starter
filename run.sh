#!/usr/bin/env bash
# SPDX-License-Identifier: 0BSD  (yours to change; no conditions)
# Run this application: GNU Emacs is its web server.
#
#   ./run.sh [PORT]        then open http://127.0.0.1:PORT/  (default 8018)
#   PUBLIC_ORIGIN=https://example.com ./run.sh
#                          behind a reverse proxy that publishes it there
#                          (server/deploy/ has configurations)
#   WORKERS=4 ./run.sh     four Emacs processes, on PORT to PORT+3, for a
#                          proxy to spread the requests over: four cores
#   CORS_ORIGINS=https://front.example.net ./run.sh
#                          pages of that site may use /api/ (without the
#                          visitor's cookies unless CORS_CREDENTIALS=yes)
#
# Needs bash and a native GNU Emacs (29 or later; with SQLite support if
# server.el uses a database).  Emacs serves the files of this directory and
# answers /api/... with server.el.  The page's own Emacs Lisp runs in the
# browser, in an Emacs that the page downloads from the internet, or, after
# ./fetch-emacs.sh, from this directory.  Stop with C-c.
set -euo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

emacs_bin="${EMACS:-}"
if [ -z "${emacs_bin}" ]; then
  # An "emacs" on PATH that is a link into a macOS app bundle does not
  # start: take the first candidate that really runs.
  for candidate in "$(command -v emacs || true)" \
                   /Applications/Emacs.app/Contents/MacOS/Emacs \
                   /Applications/Emacs-takaxp/Emacs.app/Contents/MacOS/Emacs; do
    if [ -n "${candidate}" ] && [ -x "${candidate}" ] \
       && "${candidate}" --batch -Q --eval t >/dev/null 2>&1; then
      emacs_bin="${candidate}"
      break
    fi
  done
fi
[ -n "${emacs_bin}" ] || { echo "run.sh: no Emacs found; set EMACS=/path/to/emacs" >&2; exit 127; }

port="${1:-8018}"
workers="${WORKERS:-1}"
# A visitor who hangs up in the middle of a file must not end the server.
# Writing to a connection that the other side has closed raises SIGPIPE,
# and Emacs in batch mode leaves that signal as it finds it: by default,
# the end of the process.  Ignored here, it stays ignored in Emacs, which
# then gets an ordinary error for that one connection.
trap '' PIPE
export SERVE_PROJECT_SIGPIPE=ignored
serve() {
  exec "${emacs_bin}" --batch -Q \
    --eval "(setq serve-project-directory \"${here}/\" serve-project-port $1)" \
    -l "${here}/server/serve-project.el" -f serve-project-run
}
if [ "${workers}" -le 1 ]; then
  serve "${port}"
else
  # One Emacs uses one core.  WORKERS of them, on PORT, PORT+1, ...; the
  # reverse proxy in front spreads the requests over them.
  pids=""
  trap 'kill ${pids} 2>/dev/null' EXIT
  trap 'exit 0' INT TERM
  worker=0
  while [ "${worker}" -lt "${workers}" ]; do
    serve "$((port + worker))" &
    pids="${pids} $!"
    worker=$((worker + 1))
  done
  # If one of them ends, all end: whatever keeps this script running
  # (systemd) then starts them again together.
  while :; do
    for pid in ${pids}; do
      kill -0 "${pid}" 2>/dev/null || exit 1
    done
    sleep 1
  done
fi
