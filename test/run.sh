#!/usr/bin/env bash
# SPDX-License-Identifier: 0BSD  (yours to change; no conditions)
# Check the application with a native GNU Emacs (29 or later, with SQLite):
#
#   test/run.sh
#
# 1. routes.el and index.html's scripts are up to date with pages/, api/
#    and shared/ (vendor/elisp-next/bin/nextel-routes --check);
# 2. every .el file of the project compiles without a warning, the page's
#    and the server's each in an Emacs of its own (test/lint.el);
# 3. the tests pass: the server and the pages in one Emacs, no browser
#    (test/*-test.el).
#
# Everything it uses is in the project; no network.  EMACS=/path/to/emacs
# chooses the Emacs.  The browser test is npm run test:e2e.
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.."

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
[ -n "${emacs_bin}" ] || { echo "test/run.sh: no Emacs found; set EMACS=/path/to/emacs" >&2; exit 127; }
"${emacs_bin}" --batch -Q --eval '(unless (and (fboundp (quote sqlite-available-p)) (sqlite-available-p)) (kill-emacs 1))' \
  || { echo "test/run.sh: $("${emacs_bin}" --version | head -1) has no SQLite; use Emacs 29 or later built with it" >&2; exit 1; }
echo "$("${emacs_bin}" --version | head -1)"

echo "routes:"
EMACS="${emacs_bin}" vendor/elisp-next/bin/nextel-routes --check

echo "lint:"
"${emacs_bin}" --batch -Q -l test/lint.el --eval '(starter-lint "page")'
"${emacs_bin}" --batch -Q -l test/lint.el --eval '(starter-lint "server")'

echo "tests:"
tests=()
for file in test/*-test.el; do tests+=("-l" "${file}"); done
"${emacs_bin}" --batch -Q "${tests[@]}" -f ert-run-tests-batch-and-exit
