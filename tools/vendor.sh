#!/usr/bin/env bash
# SPDX-License-Identifier: 0BSD  (yours to change; no conditions)
# Put the versions that VERSIONS names into the project, from GitHub:
#
#   vendor/elisp-next/    elisp-next: lisp/, bin/nextel-routes, doc/api.md (+ .ja), SKILL.md, LICENSE
#   vendor/elisp-react/   elisp-react: js/elisp-react.js, lisp/react.el, lisp/react-testing.el,
#                         doc/api.md (+ .ja), SKILL.md, LICENSE
#   server/               elisp-studio: serve-project.el, app-server.el, serve-cgi.el, README.md
#                         (the reference of app-server.el), LICENSE, cgi/ and deploy/
#   run.sh, backup.sh, Dockerfile, docker-compose.yml, .dockerignore   elisp-studio's kit
#   test/lib/cdp.mjs      elisp-react's Chrome DevTools helpers, for test/e2e.mjs
#
#   tools/vendor.sh            replace them with what VERSIONS names
#   tools/vendor.sh --check    only compare: exit 1 if one differs (CI runs this)
#
# Each directory gets a VERSION file that says where it came from.  Do not
# edit these files by hand: change VERSIONS and run this again, then
# vendor/elisp-next/bin/nextel-routes, test/run.sh and npm run test:e2e.
# The browser's Emacs (WASMACS) is not kept in git: fetch-emacs.sh.
#
# Needs bash, curl and tar.
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.."
check=no
case "${1:-}" in
  "") ;;
  --check) check=yes ;;
  *) echo "usage: tools/vendor.sh [--check]" >&2; exit 2 ;;
esac

pin() {  # pin NAME: its value in VERSIONS
  local value
  value="$(sed -n "s/^$1=//p" VERSIONS)"
  [ -n "${value}" ] || { echo "tools/vendor.sh: VERSIONS has no $1" >&2; exit 1; }
  printf '%s' "${value}"
}
next="$(pin ELISP_NEXT)"
react="$(pin ELISP_REACT)"
studio="$(pin ELISP_STUDIO)"

work="$(mktemp -d)"
trap 'rm -rf "${work}"' EXIT
out="${work}/out"

fetch() {  # fetch REPOSITORY REF: modeverv/REPOSITORY at REF, into the work directory
  echo "${1} ${2}"
  mkdir -p "${work}/${1}"
  curl -fsSL --retry 3 "https://codeload.github.com/modeverv/${1}/tar.gz/${2}" \
    | tar -xz --strip-components=1 -C "${work}/${1}"
}
put() {  # put REPOSITORY/PATH DESTINATION [MODE]
  mkdir -p "$(dirname "${out}/${2}")"
  cp "${work}/${1}" "${out}/${2}"
  chmod "${3:-644}" "${out}/${2}"
}
origin() {  # origin DIRECTORY REPOSITORY REF: DIRECTORY/VERSION
  printf '%s\nhttps://github.com/modeverv/%s/tree/%s\n' "${3}" "${2}" "${3}" > "${out}/${1}/VERSION"
}

fetch elisp-next "${next}"
for file in nextel.el nextel-build.el nextel-route.el nextel-schema.el nextel-server.el; do
  put "elisp-next/lisp/${file}" "vendor/elisp-next/lisp/${file}"
done
put elisp-next/bin/nextel-routes vendor/elisp-next/bin/nextel-routes 755
for file in doc/api.md doc/api.ja.md SKILL.md LICENSE; do
  put "elisp-next/${file}" "vendor/elisp-next/${file}"
done
origin vendor/elisp-next elisp-next "${next}"

fetch elisp-react "${react}"
for file in js/elisp-react.js lisp/react.el lisp/react-testing.el doc/api.md doc/api.ja.md SKILL.md LICENSE; do
  put "elisp-react/${file}" "vendor/elisp-react/${file}"
done
origin vendor/elisp-react elisp-react "${react}"
# Chrome DevTools helpers for test/e2e.mjs (MIT, vendor/elisp-react/LICENSE).
put elisp-react/test/lib/cdp.mjs test/lib/cdp.mjs

fetch elisp-studio "${studio}"
put elisp-studio/tools/serve-project.el server/serve-project.el
put elisp-studio/lisp/app-server.el server/app-server.el
put elisp-studio/tools/serve-cgi.el server/serve-cgi.el
put elisp-studio/README.md server/README.md
put elisp-studio/LICENSE server/LICENSE
for file in deploy.sh install.sh make-mycnf.sh; do
  put "elisp-studio/tools/project/cgi/${file}" "server/cgi/${file}" 755
done
put elisp-studio/tools/project/cgi/htaccess server/cgi/htaccess
for file in Caddyfile nginx.conf app.service; do
  put "elisp-studio/tools/project/deploy/${file}" "server/deploy/${file}"
done
put elisp-studio/tools/project/deploy/docker-start.sh server/deploy/docker-start.sh 755
put elisp-studio/tools/project/run.sh run.sh 755
put elisp-studio/tools/project/backup.sh backup.sh 755
put elisp-studio/tools/project/Dockerfile Dockerfile
put elisp-studio/tools/project/docker-compose.yml docker-compose.yml
put elisp-studio/tools/project/dockerignore .dockerignore
origin server elisp-studio "${studio}"

managed=(vendor/elisp-next vendor/elisp-react test/lib/cdp.mjs server run.sh backup.sh Dockerfile docker-compose.yml .dockerignore)
if [ "${check}" = yes ]; then
  differ=no
  for path in "${managed[@]}"; do
    diff -r -x '*.elc' "${out}/${path}" "${path}" >/dev/null 2>&1 || { echo "differs from VERSIONS: ${path}"; differ=yes; }
  done
  [ "${differ}" = no ] || { echo "tools/vendor.sh: run tools/vendor.sh to put what VERSIONS names" >&2; exit 1; }
  echo "tools/vendor.sh: the vendored files are those of VERSIONS"
else
  for path in "${managed[@]}"; do
    rm -rf "${path}"
    mkdir -p "$(dirname "${path}")"
    cp -Rp "${out}/${path}" "${path}"
  done
  echo "tools/vendor.sh: put elisp-next ${next:0:7}, elisp-react ${react:0:7}, elisp-studio ${studio:0:7}"
fi
