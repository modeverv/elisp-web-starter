#!/bin/sh
# SPDX-License-Identifier: 0BSD  (yours to change; no conditions)
# Write my.cnf, the MySQL settings of the application, on the host:
#
#   ssh -t HOST sh APP-DIR/server/cgi/make-mycnf.sh MYSQL-HOST
#
# Run it yourself: the password is typed here, not shown, and kept only in
# that file (mode 600, in APP-DIR, outside the web root).  app.cgi gives
# its path to the server (APP_MYSQL); nothing else holds the password.
set -e
umask 077
here="$(cd "$(dirname "$0")/../.." && pwd)"
cnf="$here/my.cnf"
host="${1:?usage: make-mycnf.sh MYSQL-HOST}"
printf 'MySQL user: '; read user
printf 'Database name: '; read database
stty -echo; printf 'Password (not shown): '; read password; stty echo; echo
printf '[client]\nhost=%s\nuser=%s\npassword=%s\ndefault-character-set=utf8mb4\n\n[mysql]\ndatabase=%s\n' \
  "$host" "$user" "$password" "$database" > "$cnf"
chmod 600 "$cnf"
ls -l "$cnf"
echo "Testing the connection:"
mysql --defaults-extra-file="$cnf" -e 'SELECT VERSION() AS version, DATABASE() AS db, CURRENT_USER() AS user'
echo "Deploy again (server/cgi/deploy.sh) for app.cgi to use it."
