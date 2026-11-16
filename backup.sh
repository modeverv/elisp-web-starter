#!/usr/bin/env bash
# SPDX-License-Identifier: 0BSD  (yours to change; no conditions)
# Copy what this application keeps (.data/) to a place of its own, while
# the server runs.
#
#   ./backup.sh [DIRECTORY]     default: .backups/DATE-TIME/ in this directory
#
# The databases are copied by SQLite itself (VACUUM INTO), which gives a
# whole database also in the middle of a write; a plain cp of a database
# in use may not.  Everything else is copied as it is.  .backups/ is not
# served, but it is on the same disk: copy it somewhere else.
set -euo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
data="${here}/.data"
target="${1:-${here}/.backups/$(date +%Y%m%d-%H%M%S)}"
[ -d "${data}" ] || { echo "backup.sh: there is no .data/ here: nothing is kept yet" >&2; exit 1; }

emacs_bin="${EMACS:-}"
if [ -z "${emacs_bin}" ]; then
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
[ -n "${emacs_bin}" ] || { echo "backup.sh: no Emacs found; set EMACS=/path/to/emacs" >&2; exit 127; }

mkdir -p "${target}"
chmod 700 "${target}"
target="$(cd "${target}" && pwd)"
# Lisp data and kept files.
for file in "${data}"/*.eld; do
  [ -e "${file}" ] && cp -p "${file}" "${target}/"
done
[ -d "${data}/files" ] && cp -Rp "${data}/files" "${target}/files"
# Databases.
for database in "${data}"/*.db; do
  [ -e "${database}" ] || continue
  DATABASE="${database}" COPY="${target}/$(basename "${database}")" "${emacs_bin}" --batch -Q --eval '
    (let ((database (sqlite-open (getenv "DATABASE"))))
      (sqlite-pragma database "busy_timeout = 10000")
      (sqlite-execute database "VACUUM INTO ?" (list (getenv "COPY")))
      (sqlite-close database))'
done
echo "backup.sh: ${target}"
