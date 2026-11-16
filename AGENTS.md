# Working on this project

A web application written in Emacs Lisp on both sides, with [elisp-next](https://github.com/modeverv/elisp-next):

- **The page** runs in GNU Emacs 30.2 compiled to WebAssembly, inside the browser tab. Its components are [elisp-react](https://github.com/modeverv/elisp-react)'s (React in Emacs Lisp).
- **The server** is a native GNU Emacs (`./run.sh`), on [elisp-studio](https://github.com/modeverv/elisp-studio)'s `app-server.el`. It keeps the data in SQLite (MySQL on a shared host).
- **Between them** are record types that both sides check (`shared/`).

The application is a list of notes. You can write, search, mark done, read, change and delete them. It is meant to be changed into your own application.

## Commands

Run each from the project's root.

| Command | What it does |
|---|---|
| `./run.sh [PORT]` | Serves the application at `http://127.0.0.1:8018/` (or PORT). Data goes in `.data/app.db`. Stop it with Ctrl-C. A change to `api/` or `shared/` takes effect when you start it again; a change to `pages/` takes effect when you reload the page. |
| `test/run.sh` | The check. **It must pass before you finish.** It does three things: checks that the routes are up to date, compiles every `.el` file of the page and of the server with warnings as errors, and runs the ERT tests (`test/*-test.el`: server and pages in one native Emacs, no browser, no network). |
| `npm run test:e2e` | The application in headless Chrome (`test/e2e.mjs`): a copy of the project behind `./run.sh`, the page's Emacs as WebAssembly. Run it after changing `pages/`, `style.css` or `index.html`. It needs Chrome, and the internet unless `./fetch-emacs.sh` ran. |
| `vendor/elisp-next/bin/nextel-routes` | Writes `routes.el` and the script tags of `index.html`. Run it after adding, removing or renaming a file of `pages/`, `api/` or `shared/`, or after renaming a page's component. `--check` only compares. |
| `curl http://127.0.0.1:8018/api/notes` | The API answers in printed Lisp data. To send data: `curl -X POST --data '(:title "Milk")' http://127.0.0.1:8018/api/notes`. |
| `./fetch-emacs.sh [--core]` | Puts the browser's Emacs of `VERSIONS` into `vendor/wasmacs/` (170 MB, or 45 MB with `--core`). `./run.sh` then serves it, and the page needs no internet. |
| `tools/vendor.sh [--check]` | Puts the libraries of `VERSIONS` into `vendor/` and `server/`. `--check` only compares; CI runs it. |

## Read before writing code, in this order

1. This file.
2. [`vendor/elisp-next/doc/api.md`](vendor/elisp-next/doc/api.md) covers pages, API routes, schemas, the routes writer and testing. Read its **Rules and pitfalls** in full, once. In Japanese: `doc/api.ja.md` next to it.
3. [`vendor/elisp-react/doc/api.md`](vendor/elisp-react/doc/api.md) covers components, `jsx`, state, events, async code and `react-testing`. Its **Rules and pitfalls** too.
4. [`server/README.md`](server/README.md), elisp-studio's README, section "A server side". It describes `app-server.el`: SQL (`app-server-sql-*`), sessions and passwords, uploads, jobs, and deployment.

These describe exactly the versions in this project (`VERSIONS`). Do not carry React or Next.js over by guessing: what these documents do not describe does not exist. The code here follows them. When you are unsure how to do something, look at how the notes do it first.

## Where things are

```text
shared/starter-types.el   the types: starter-note, starter-draft (what the page sends), starter-health;
                          starter-check-draft, the check that both sides run
api/_notes.el             the server's functions: the table, SQL, finding, adding, changing, deleting
api/notes.el              GET /api/notes?q=TEXT, POST /api/notes
api/notes/[id].el         GET, PUT, DELETE /api/notes/ID
api/health.el             GET /api/health
pages/_layout.el          around every page: header, footer, the document's title
pages/_parts/             the pages' helpers: NoteForm (new and changed notes), dates, excerpts
pages/index.el            /                (HomePage: the list, the search, a new note)
pages/notes/[id].el       /notes/ID        (NotePage: read, change, delete)
pages/about.el            /about           (AboutPage: GET /api/health)
pages/404.el              any other address
routes.el                 written by nextel-routes: never edit it by hand
index.html                the page; nextel-routes fills its two marked regions
server.el                 three lines that load elisp-next's server; leave it as it is
style.css                 the look (light and dark)
test/starter-test.el      the tests: the API, and the pages with the server behind them
test/lint.el, run.sh      the check; test/e2e.mjs, the browser test
VERSIONS                  the pinned versions
vendor/, server/          the libraries of VERSIONS (tools/vendor.sh): never edit them by hand
```

## Adding a feature

For example, tags on notes, or a second kind of record:

1. **Type**: `nextel-defschema` in `shared/` (a new file is fine). Add a check like `starter-check-draft` for what types cannot say.
2. **Server**: the functions go in a helper of `api/` (`api/_name.el`). The SQL tables go in `starter-tables`, for both SQLite and MySQL. Then add one route file per address (`api/things.el`, `api/things/[id].el`), with `(nextel-handle "METHOD" :accepts TYPE :returns TYPE :handler ...)`. Refuse with `(app-server-refuse "Why" STATUS)`.
3. **Page**: `pages/NAME.el` with `(nextel-page NamePage ...)` as its first form. Load data with `:load` and `nextel-request`. After a change, call `(nextel-reload)`. Components that more than one page uses go in `pages/_parts/`.
4. **Routes**: `vendor/elisp-next/bin/nextel-routes`.
5. **Tests**: add to `test/starter-test.el`. Call the server with `starter-test-call`, and drive the pages with `starter-test-start`, `react-testing-input`, `react-testing-submit`, `react-testing-click`, then `starter-test-serve`, which answers the page's requests with the server.
6. **Check**: `test/run.sh`. If a page changed, also `npm run test:e2e`, with a step added there for what a visitor now does.

## Rules this project adds

The documents above have the rest.

- **Prefix.** The project's Lisp uses the prefix `starter-`. To make your own application of it, either keep it or rename it everywhere, tests included.
- **Shared functions.** What more than one route needs goes in `api/_*.el`, never in a route file. On a shared host, only the route file that answers a request is loaded.
- **One Emacs in the tests.** The tests load the page and the server into one Emacs. A name defined on both sides differently breaks them, so keep page and server function names apart.
- **Schema names.** A schema's accessors share the namespace: `starter-note-FIELD` and the like belong to `nextel-defschema`. Name helpers outside them (`starter-line`, not `starter-note-line`).
- **SQL values.** Values reach SQL as `?` parameters only, never inside the SQL text.
- **The visitor's time.** The page's Emacs runs in UTC and in the C locale. The visitor's time zone comes from `(react-locale :offset)`; see `starter-date`.
- **Classes for tests.** `react-testing-find` takes the first match in document order. Give an element that a test looks for a class that nothing around it has.
- **Vendored files.** Do not edit `vendor/`, `server/`, `run.sh`, `backup.sh`, `Dockerfile`, `docker-compose.yml`, `.dockerignore` or `test/lib/cdp.mjs`. `tools/vendor.sh` writes them from `VERSIONS`, and CI fails when they differ. To move to another version, change `VERSIONS`, run `tools/vendor.sh`, then the tests.

## Done means

- `test/run.sh` passes, and the new behaviour has a test.
- `npm run test:e2e` passes if a page changed.
- `tools/vendor.sh --check` passes.

## Requirements

- **To run and test:** bash and GNU Emacs 29 or later with SQLite. On macOS that is Homebrew's `emacs` or Emacs.app; on Ubuntu, `apt install emacs-nox`. `EMACS=/path/to/emacs` chooses one.
- **For the browser test:** Node 24 or later and Chrome (`CHROME_PATH`).
- **On a shared host (CGI):** Emacs 27.2 or later, and MySQL.
