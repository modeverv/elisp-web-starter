# SPDX-License-Identifier: 0BSD  (yours to change; no conditions)
# This application in a container: GNU Emacs is its web server (run.sh, four
# processes), and Caddy is in front of it in the same container, since the
# server listens on 127.0.0.1 only.  docker-compose.yml starts it; by hand:
#
#   docker build -t app . && docker run -p 8080:80 app       http://localhost:8080/
#
# Ubuntu 24.04 has GNU Emacs 29.3, with SQLite for server.el, and python3,
# which hashes passwords twenty times faster than Lisp.  Caddy is the binary
# of its official image.
FROM caddy:2 AS caddy

FROM ubuntu:24.04
RUN apt-get update \
 && DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends emacs-nox python3 ca-certificates \
 && rm -rf /var/lib/apt/lists/* \
 && useradd --system --create-home app
COPY --from=caddy /usr/bin/caddy /usr/bin/caddy
# The application's files belong to root: the server, which runs as app,
# writes .data/ and nothing else (a volume in docker-compose.yml).
COPY . /srv/app
RUN mkdir -p /srv/app/.data && chown app:app /srv/app/.data
WORKDIR /srv/app
# Caddy keeps its certificates here (also a volume).
ENV XDG_DATA_HOME=/data XDG_CONFIG_HOME=/config
EXPOSE 80 443
CMD ["bash", "server/deploy/docker-start.sh"]
