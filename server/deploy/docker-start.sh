#!/usr/bin/env bash
# SPDX-License-Identifier: 0BSD  (yours to change; no conditions)
# The container's first process (Dockerfile, docker-compose.yml): Caddy in
# front, with server/deploy/Caddyfile, and run.sh behind it with four Emacs
# processes as the user app.  When either ends, the other is stopped and
# the container ends, for Docker to start it again.
#
#   DOMAIN=example.com   HTTPS for that name: Caddy gets the certificate
#   no DOMAIN            plain HTTP on port 80 of the container
#   PUBLIC_ORIGIN        the address visitors use; by default https://DOMAIN
#                        or http://localhost:HTTP_PORT (HTTP_PORT, HTTPS_PORT:
#                        the machine's ports, as docker-compose.yml maps them)
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/../.."

if [ -n "${DOMAIN:-}" ]; then
  export SITE_ADDRESS="${DOMAIN}"
  port="${HTTPS_PORT:-443}"
  default_origin="https://${DOMAIN}$([ "${port}" = 443 ] || echo ":${port}")"
else
  export SITE_ADDRESS=":80"
  port="${HTTP_PORT:-8080}"
  default_origin="http://localhost$([ "${port}" = 80 ] || echo ":${port}")"
fi
origin="${PUBLIC_ORIGIN:-${default_origin}}"
echo "docker-start: ${SITE_ADDRESS} in the container, published as ${origin}"

# A new volume for .data/ belongs to root; the server writes it as app.
mkdir -p .data
chown app:app .data

caddy run --config server/deploy/Caddyfile --adapter caddyfile &
caddy=$!
runuser -u app -- env PUBLIC_ORIGIN="${origin}" CORS_ORIGINS="${CORS_ORIGINS:-}" \
  CORS_CREDENTIALS="${CORS_CREDENTIALS:-}" WORKERS=4 PROXY_SENDS_FILES=yes bash ./run.sh 8018 &
app=$!

trap 'kill -TERM "${caddy}" "${app}" 2>/dev/null || true' TERM INT
status=0
wait -n "${caddy}" "${app}" || status=$?
kill -TERM "${caddy}" "${app}" 2>/dev/null || true
wait || true
exit "${status}"
