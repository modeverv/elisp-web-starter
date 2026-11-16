#!/bin/sh
# SPDX-License-Identifier: 0BSD  (yours to change; no conditions)
# Put this project on a shared host that runs CGI programs and allows no
# server of one's own (Sakura's rental server, for one), over SSH:
#
#   server/cgi/deploy.sh SSH-HOST WEB-DIR APP-DIR PUBLIC-ORIGIN
#   server/cgi/deploy.sh myhost www/todos todos-app https://example.com
#
# WEB-DIR (under the web root; relative to the home directory) gets the
# page's files, app.cgi and .htaccess.  APP-DIR (outside it) gets the whole
# project: server.el and what it loads, server/, the data directory
# (data/), and my.cnf if the data is in MySQL (server/cgi/make-mycnf.sh).
# The host's Emacs (27.2 or later) compiles server/ there.  Run it from the
# project's directory; run it again after a change.
#
# APP-DIR/job.sh runs the jobs of server.el (app-server-defjob): give it
# to cron, every 10 minutes say.
set -eu
usage="usage: deploy.sh SSH-HOST WEB-DIR APP-DIR PUBLIC-ORIGIN"
host="${1:?$usage}"; web="${2:?$usage}"; app="${3:?$usage}"; origin="${4:?$usage}"
[ -f index.html ] && [ -f server/serve-cgi.el ] || { echo "deploy.sh: run it in the project's directory" >&2; exit 2; }
case "$web$app" in *[!A-Za-z0-9_./-]*) echo "deploy.sh: WEB-DIR and APP-DIR are plain relative paths" >&2; exit 2;; esac
case "$origin" in https://*|http://*) ;; *) echo "deploy.sh: PUBLIC-ORIGIN is https://NAME" >&2; exit 2;; esac
incoming=".deploy-$$"
# The project, without what is not for the host, unpacked there and put in
# place by install.sh.  The command is one that csh (the login shell of
# some hosts) runs as sh would.
COPYFILE_DISABLE=1 tar -cf - --exclude ./.git --exclude ./.data --exclude ./.cache --exclude ./my.cnf \
    --exclude '*.elc' --exclude ./node_modules . \
  | ssh "$host" "mkdir -p $incoming && tar -xf - -C $incoming && sh $incoming/server/cgi/install.sh $incoming $web $app $origin"
