---
name: elisp-next
description: Build web applications with elisp-next, the Next.js-like layer of elisp-react (React written in Emacs Lisp; GNU Emacs runs in the web page as WebAssembly). A file in pages/ is an address, a file in api/ is a server route, and shared/ holds record types that the page and the server both check. Use when creating or changing an elisp-next project, a page (nextel-page), the layout, an API route (nextel-handle), a schema (nextel-defschema), a request (nextel-request), routes.el or index.html's script tags, or any code that uses a nextel- symbol.
---

# elisp-next

**Before you write or change any code, read [doc/api.md](doc/api.md).** It is the complete API of elisp-next, written from the code; every example in it was run. Do not guess: a function, keyword, key or behaviour that doc/api.md does not describe does not exist. Where doc/api.md and README.md differ, doc/api.md is right.

If doc/api.md is not next to this file, read <https://raw.githubusercontent.com/modeverv/elisp-next/main/doc/api.md>.

The components of the pages are elisp-react's: also read elisp-react's API, <https://raw.githubusercontent.com/modeverv/elisp-react/main/doc/api.md> (or the `elisp-react` skill), before writing `:render`, events or state.

## What to read for what

| You are about to | Read in doc/api.md |
|---|---|
| start a project, or add files | [Project layout](doc/api.md#project-layout), [Worked example](doc/api.md#worked-example) |
| write a page or the layout | [Pages](doc/api.md#pages), [Addresses and navigation](doc/api.md#addresses-and-navigation) |
| load data for a page | [`:load`](doc/api.md#load), [Requests](doc/api.md#requests) |
| define a record type | [Schemas](doc/api.md#schemas) |
| answer a request on the server | [Server](doc/api.md#server), [From elisp-react and app-server.el](doc/api.md#from-elisp-react) |
| add, remove or rename a page | [Routes writer](doc/api.md#routes-writer) |
| test the application | [Testing an application](doc/api.md#testing) |
| anything | [Rules and pitfalls](doc/api.md#pitfalls), all of them, once |

## Workflow

1. Lay the project out as the [worked example](doc/api.md#worked-example) does: `index.html` with its two marker regions, `pages/`, `api/`, `shared/`, `server.el`, and a copy of elisp-next in `vendor/elisp-next/`.
2. Types first, in `shared/` (`nextel-defschema`): the page and the server load the same file.
3. Pages in `pages/`: one `(nextel-page Name ...)` per file, as the first form, with the name Capitalized and unquoted. `pages/channel/[id].el` is `/channel/ID`.
4. Routes in `api/`: `(nextel-handle "GET" :returns TYPE :handler ...)`, `:accepts` for a body.
5. Write the routes after adding, removing or renaming a page or a `shared/` file: `vendor/elisp-next/bin/nextel-routes`, or `M-x nextel-write-routes`.
6. Check: run the tests as [Testing an application](doc/api.md#testing) shows, and `vendor/elisp-next/bin/nextel-routes --check`. Every `.el` file should compile without a warning.
7. Run it: `../elisp-studio/tools/serve-project.sh . PORT` (a native Emacs), or open the project in elisp-studio.

## Rules that are easy to break

These are a selection; [Rules and pitfalls](doc/api.md#pitfalls) has all 27 with the reasons.

- The prefix is `nextel-`, not `next-`. Give your own code a prefix of its own.
- Every file starts with `-*- lexical-binding: t; -*-`.
- `:load` returns a function of RESOLVE and REJECT, such as `(nextel-request "GET" ...)`, not a `react-async` task.
- A page's data is kept by page, params and query, and loaded again in the background when the router comes back after `nextel-stale-ms` (60 s). After a request that changed data, call `(nextel-reload)`.
- `nextel-defschema NAME` defines `make-NAME`, `NAME-p` and `NAME-FIELD`. These share your namespace, so name your own functions so that they cannot clash.
- Keywords go in (`nextel-href`, `nextel-param`: `:id`), strings come out (`nextel-query self "v"`; parameters are strings).
- `server.el` is three lines, including `(declare-function nextel-server-load "nextel-server")`.
- An error in a handler is a 400. Refuse on purpose with `app-server-refuse` and a status.
- What more than one route needs (functions, variables, `app-server-defjob`) goes in `shared/` or a helper of api/ (`api/_name.el`): on a shared host a route file is loaded only when its own request comes.
