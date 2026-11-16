#!/usr/bin/env bash
# SPDX-License-Identifier: 0BSD  (yours to change; no conditions)
# Put the Emacs that runs in the browser into vendor/wasmacs/: the build
# that VERSIONS names (WASMACS, a commit of github.com/modeverv/wasmacs),
# so that ./run.sh serves it itself and the page needs no internet.
#
#   ./fetch-emacs.sh          about 170 MB: Emacs with all of its Lisp
#   ./fetch-emacs.sh --core   about 45 MB: with the language's library only
#
# Without it the page takes Emacs from https://modeverv.github.io/wasmacs/,
# which is always the newest build.  With it, the one this project was
# tested with: serve-project.el (server/) then tells the page to use
# /vendor/wasmacs/.  vendor/wasmacs/ is not kept in git (.gitignore).
#
# What lies here is not what a visitor downloads: a visitor gets Emacs
# itself (5 MB, compressed copies made below) and, of its Lisp, the files
# the page reads.  --core leaves out the editor's own libraries (Org, Calc,
# the programming modes, sources); a page that requires one of those fails
# with "Cannot open load file".  This application needs none.
#
# Needs bash, curl and gzip.  A site that serves vendor/wasmacs/ distributes
# GNU Emacs, under the GPL: vendor/wasmacs/licenses/ (the licence texts and
# NOTICE.txt, which says where the source of the build is) comes along and
# has to stay with it.  Derived from elisp-studio's fetch-emacs.sh.
set -euo pipefail
package=full
case "${1:-}" in
  ""|--full) ;;
  --core) package=core ;;
  *) echo "usage: ./fetch-emacs.sh [--core]" >&2; exit 2 ;;
esac
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
pin() { sed -n "s/^$1=//p" "${here}/VERSIONS"; }
commit="$(pin WASMACS)"
build="$(pin WASMACS_BUILD)"
[ -n "${commit}" ] || { echo "fetch-emacs.sh: VERSIONS has no WASMACS" >&2; exit 1; }
wasmacs="${WASMACS_URL:-https://raw.githubusercontent.com/modeverv/wasmacs/${commit}/docs/}"
target="${here}/vendor/wasmacs"
fresh="${here}/vendor/.wasmacs.part"
rm -rf "${fresh}"
trap 'rm -rf "${fresh}"' EXIT

fetch() {  # fetch PATH: BASE-URL/PATH into the new copy
  mkdir -p "$(dirname "${fresh}/$1")"
  curl -fsSL --retry 3 -o "${fresh}/$1" "${wasmacs}$1"
}

echo "Emacs from ${wasmacs}"
emacs_dir=artifacts/emacs-browser-atomics-pdump
for path in app/eval-build-id.json \
            app/src/emacs-eval-client.js app/src/emacs-eval-worker.js \
            app/src/emacs-eval-core.js app/src/wasmacs-eval-service.el \
            "${emacs_dir}/temacs.js" "${emacs_dir}/temacs.wasm" "${emacs_dir}/bootstrap-emacs.pdmp" \
            licenses/files.txt; do
  fetch "${path}"
done
if [ -n "${build}" ] && ! grep -q "\"${build}\"" "${fresh}/app/eval-build-id.json"; then
  echo "fetch-emacs.sh: the build is $(cat "${fresh}/app/eval-build-id.json"), not ${build} of VERSIONS" >&2
  exit 1
fi
if [ "${package}" = full ]; then
  # Emacs's Lisp: temacs.files.json says which files there are and where;
  # the package comes in parts, named in the manifest.
  fetch "${emacs_dir}/temacs.files.json"
  fetch "${emacs_dir}/temacs.data.parts/manifest.json"
  for part in $(grep -o '"name": *"[^"]*"' "${fresh}/${emacs_dir}/temacs.data.parts/manifest.json" | sed 's/.*"\([^"]*\)"$/\1/'); do
    case "${part}" in *[!A-Za-z0-9._-]*|.*) echo "fetch-emacs.sh: not a file name: ${part}" >&2; exit 1 ;; esac
    echo "  ${part}"
    fetch "${emacs_dir}/temacs.data.parts/${part}"
  done
else
  fetch "${emacs_dir}/temacs.core.data"
  fetch "${emacs_dir}/temacs.core.files.json"
  mv "${fresh}/${emacs_dir}/temacs.core.files.json" "${fresh}/${emacs_dir}/temacs.files.json"
  # A browser keeps what it downloaded under this id: the smaller package
  # is another set of files than the whole one of the same build.
  sed -i.bak 's/\("id": *"[^"]*\)"/\1-core"/' "${fresh}/app/eval-build-id.json"
  rm -f "${fresh}/app/eval-build-id.json.bak"
fi
# A compressed copy next to each large file that every visitor downloads:
# the server sends that one to a browser that takes gzip (16 MB become 5).
for name in temacs.wasm bootstrap-emacs.pdmp temacs.js temacs.files.json; do
  gzip -9 -c "${fresh}/${emacs_dir}/${name}" > "${fresh}/${emacs_dir}/${name}.gz"
done
# The licences of what was just copied, and where its source is.
for name in $(cat "${fresh}/licenses/files.txt"); do
  case "${name}" in *[!A-Za-z0-9._-]*|.*) echo "fetch-emacs.sh: not a file name: ${name}" >&2; exit 1 ;; esac
  fetch "licenses/${name}"
done
printf '%s\nhttps://github.com/modeverv/wasmacs/tree/%s\n' "${commit}" "${commit}" > "${fresh}/VERSION"
rm -rf "${target}"
mv "${fresh}" "${target}"
trap - EXIT
echo "done: $(du -sh "${target}" | cut -f1) in vendor/wasmacs/ (wasmacs ${commit:0:7}).  ./run.sh now serves it."
echo "Emacs is free software under the GNU GPL: see vendor/wasmacs/licenses/NOTICE.txt"
