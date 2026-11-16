# elisp-next API

The complete API of elisp-next, written so that a coding agent can build an application with it without guessing. It assumes Next.js, React and Emacs Lisp, and nothing about elisp-next or elisp-react.

It describes v0.1.2, the `lisp/` of `main`. v0.1.1 loaded every file of api/ at the start, also under a CGI, and only from source. v0.1.0 differs in three more places, each said where it applies: `nextel-stale-ms` had no effect, the server loaded hidden files of api/, and a method fell through to a less specific file. Every message, value and piece of HTML quoted below was produced by running the code in GNU Emacs 31.1 in batch, with elisp-react's `react-testing.el` for the page side and elisp-studio's `app-server.el` for the server side; the [worked example](#worked-example) was run the same way, served with `serve-project.sh` and used in Chrome.

elisp-next sits on two libraries: [elisp-react](https://github.com/modeverv/elisp-react) (React written in Emacs Lisp; GNU Emacs runs in the web page as WebAssembly) and [elisp-studio](https://github.com/modeverv/elisp-studio)'s `app-server.el` (the server). The parts of them an application needs are in [From elisp-react and app-server.el](#from-elisp-react); their READMEs have the rest.

1. [Index](#index)
2. [Mental model](#mental-model)
3. [Project layout](#project-layout)
4. [Pages](#pages)
5. [Addresses and navigation](#addresses-and-navigation)
6. [Patterns](#patterns)
7. [Requests](#requests)
8. [Schemas](#schemas)
9. [Server](#server)
10. [Routes writer](#routes-writer)
11. [From elisp-react and app-server.el](#from-elisp-react)
12. [Testing an application](#testing)
13. [Rules and pitfalls](#pitfalls)
14. [Worked example](#worked-example)

## Index

Every symbol that elisp-next's five files define without `--` in its name: 53 names, 54 entries (`nextel-layout` is a macro and a variable). Where it exists: **P** the page (index.html loads it), **S** the server (server.el loads it), **E** the Emacs that writes the routes (yours, elisp-studio's, or one in batch).

| Symbol | Kind | Where | Purpose |
|---|---|---|---|
| [`Link`](#link) | component | P | A link: an `<a>`; in `path` mode Lisp follows it. |
| [`nextel`](#nextel-group) | custom group | E | The group of `nextel-routes-mode`. |
| [`nextel-base-path`](#nextel-base-path) | variable | P | The application's path prefix in `path` mode. |
| [`nextel-check`](#nextel-check) | function | P S | VALUE if it is of TYPE, else signal `nextel-type-error`. |
| [`nextel-check-routes`](#nextel-check-routes) | function | E | Batch: exit 1 when routes.el or index.html is not up to date. |
| [`nextel-data`](#nextel-data) | function | P | What the page's `:load` answered. |
| [`nextel-define-routes`](#nextel-define-routes) | function | P | Install the route table, the layout and the 404 page (routes.el calls it). |
| [`nextel-defschema`](#nextel-defschema) | macro | P S | Define a record type: constructor, predicate, accessors. |
| [`nextel-error-function`](#nextel-error-function) | variable | P | The element of a failed `:load` when the page has no `:error`. |
| [`nextel-fill`](#nextel-fill) | function | P S E | A pattern and params → a path with a query string. |
| [`nextel-go`](#nextel-go) | function | P | Go to a pattern with params. |
| [`nextel-handle`](#nextel-handle) | function | S | In a file of api/: what a method does. |
| [`nextel-href`](#nextel-href) | function | P | The address of a page, for a link. |
| [`nextel-index-text`](#nextel-index-text) | function | E | index.html's text with its two regions filled. |
| [`nextel-layout`](#nextel-layout) | macro | P | Define the layout component. |
| [`nextel-layout`](#nextel-layout-variable) | variable | P | The layout component in use. |
| [`nextel-loading-function`](#nextel-loading-function) | variable | P | The element shown while a page without `:loading` loads. |
| [`nextel-match`](#nextel-match) | function | P S E | Whether a path matches a pattern; its params. |
| [`nextel-mount-selector`](#nextel-mount-selector) | variable | E | The selector routes.el mounts the application at. |
| [`nextel-navigate`](#nextel-navigate) | function | P | Go to an href (a new history entry, or replace). |
| [`nextel-navigate-functions`](#nextel-navigate-functions) | variable | P | Functions of ROUTE, run after a new address rendered. |
| [`nextel-not-found`](#nextel-not-found) | variable | P | The page of an address that no page has. |
| [`nextel-page`](#nextel-page) | macro | P | Define a page: a component with `:load`, `:head`, `:loading`, `:error`. |
| [`nextel-page-props-function`](#nextel-page-props-function) | variable | P | Props that every page gets besides `:route` and `:data`. |
| [`nextel-param`](#nextel-param) | function | P | A `[name]` parameter of a route. |
| [`nextel-pattern-of-file`](#nextel-pattern-of-file) | function | P S E | A file's path → its pattern. |
| [`nextel-pattern-rank`](#nextel-pattern-rank) | function | P S E | The sort key of a pattern. |
| [`nextel-pattern<`](#nextel-pattern-lessp) | function | P S E | The order in which patterns are tried. |
| [`nextel-project-root`](#nextel-project-root) | function | E | The directory above a file that has index.html and pages/. |
| [`nextel-query`](#nextel-query) | function | P | A value of the route's query string. |
| [`nextel-read-project`](#nextel-read-project) | function | E | What pages/, api/ and shared/ contain. |
| [`nextel-refresh`](#nextel-refresh) | function | P | Render the router, and so the page, again. |
| [`nextel-reload`](#nextel-reload) | function | P | Load the pages' data again. |
| [`nextel-request`](#nextel-request) | function | P | An awaitable request to an api/ route, checked against types. |
| [`nextel-resolve`](#nextel-resolve) | function | P | A path and a query string → a route. |
| [`nextel-route`](#nextel-route) | function | P | The route shown now. |
| [`nextel-router`](#nextel-router) | component | P | The router, which `nextel-start` mounts. |
| [`nextel-routes`](#nextel-routes) | variable | P | The route table in use. |
| [`nextel-routes-file`](#nextel-routes-file) | variable | E | The routes file's name, `"routes.el"`. |
| [`nextel-routes-mode`](#nextel-routes-mode) | global minor mode | E | Write the routes after every save of a file of pages/, api/ or shared/. |
| [`nextel-routes-mode-hook`](#nextel-routes-mode) | hook | E | Run when the mode is turned on or off (from `define-minor-mode`). |
| [`nextel-routes-text`](#nextel-routes-text) | function | E | The text of routes.el. |
| [`nextel-schema-fields`](#nextel-schema-fields) | function | P S | The fields of a schema. |
| [`nextel-server-handle`](#nextel-server-handle) | function | S | Answer METHOD PATH BODY from api/; becomes `app-server-handle`. |
| [`nextel-server-load`](#nextel-server-load) | function | S | Load shared/ and api/ and answer /api/ with them. |
| [`nextel-server-routes`](#nextel-server-routes) | variable | S | The API route table: the routes loaded so far. |
| [`nextel-server-lazy`](#nextel-server-lazy) | variable | S | Load a file of api/ when a request first needs it. |
| [`nextel-stale-ms`](#nextel-stale-ms) | variable | P | How long a page's data counts as fresh: older data is loaded again when the router comes back to its address. |
| [`nextel-start`](#nextel-start) | function | P | Mount the router (routes.el calls it). |
| [`nextel-title-function`](#nextel-title-function) | variable | P | The `:head` title → the document's title. |
| [`nextel-type-error`](#nextel-type-error) | error symbol | P S | What type checks signal. |
| [`nextel-type-p`](#nextel-type-p) | function | P S | Non-nil if VALUE is of TYPE. |
| [`nextel-url-mode`](#nextel-url-mode) | variable | P | Where the route is in the address: `hash` (default) or `path`. |
| [`nextel-watch-routes`](#nextel-watch-routes) | function | E | Batch: write the routes whenever the files change. |
| [`nextel-write-routes`](#nextel-write-routes) | command | E | Write routes.el and the `<script>` tags of index.html. |

Each `(nextel-defschema NAME ...)` also defines `make-NAME`, `NAME-p` and `NAME-FIELD` for each field ([details](#nextel-defschema)). Features: `nextel`, `nextel-schema`, `nextel-route`, `nextel-server`, `nextel-build`. The settings are plain `defvar`s: `setq` them.

## Mental model

An application runs in two Emacsen that share files, not memory; a third one writes the routes.

| | The page | The server |
|---|---|---|
| What | GNU Emacs 30.2 as WebAssembly in the browser tab (elisp-react) | A native Emacs (`tools/serve-project.sh`, a downloaded project's `run.sh`), or a third Emacs in elisp-studio's browser tab |
| Loads | react.el (elisp-react.js loads it first), then index.html's `<script type="text/emacs-lisp">` in document order | app-server.el, then the project's server.el |
| elisp-next | nextel-schema.el, nextel-route.el, nextel.el | nextel-server.el, which loads nextel-schema.el and nextel-route.el |
| Project files | shared/, your own Lisp, pages/, routes.el | shared/, api/ |

The writer (nextel-build.el: `M-x nextel-write-routes`, `nextel-routes-mode` or `bin/nextel-routes`) reads pages/, api/ and shared/ and writes routes.el and the script tags, because the page cannot list a directory.

**The page loads, in this order** (the routes writer writes the two regions):

1. react.el, loaded by elisp-react.js.
2. Region `nextel:framework`: `vendor/elisp-next/lisp/nextel-schema.el`, `nextel-route.el`, `nextel.el`, then every file of shared/ sorted by path.
3. Your own scripts, which you put between the two regions.
4. Region `nextel:pages`: `pages/_layout.el`, the other helpers of pages/ (names starting with `_`) sorted, the page files sorted (404.el among them), and `routes.el` last.
5. routes.el calls `(nextel-define-routes ...)` and `(nextel-start "#app")`: the router mounts and renders the page of the current address.

**A request, end to end:**

1. The router reads the address (`react-location`) and resolves it to a [route](#route-plist).
2. The page's `:load` runs with the route and returns `(nextel-request "GET" "/api/items/[id]" :id ID :returns 'demo-item)`.
3. The page fetches `api/items/ID` (hash mode: relative to the document); the body, if any, is printed Lisp.
4. The server's `app-server-respond` calls `app-server-handle`, which `nextel-server-load` made `nextel-server-handle`: it finds the api/ file whose pattern matches, and the method in it.
5. The body is read as data (`app-server-data`, never evaluated) and checked against `:accepts` (400 if wrong); the handler runs with the request plist; its answer is checked against `:returns` (500 if wrong) and printed.
6. The page reads the answer, checks it against `:returns` (a failure if wrong) and renders the page with it as `:data`.

**URL modes** (`nextel-url-mode`):

| | `hash` (default) | `path` |
|---|---|---|
| The route is in | the hash: `#/item/1?x=2` | the path and query string, under `nextel-base-path` |
| Ignored | the document's path and query string | the hash |
| `(nextel-href "/item/[id]" :id "1")` | `"#/item/1"` | `"/app/item/1"` (base path `"/app"`) |
| `Link` | an `<a>` the browser follows; the router hears the hash change | an `<a>` whose click Lisp handles (`nextel-navigate`); the browser does not load a page |
| `nextel-request` URL | relative: `api/items/1` | `BASE/api/items/1` |
| Hosting | any static host, elisp-studio's preview | the server must send index.html for every address of a page |

## Project layout

```text
index.html             the page; two marker regions that the routes writer fills
routes.el              written by the routes writer: patterns → page components; mounts the application
server.el              three lines: load nextel-server.el, call nextel-server-load
pages/                 one file per address (page side)
  _layout.el           (nextel-layout NAME ...): around every page
  404.el               (nextel-page NAME ...): the page of an address that no file has
  index.el             /
  item/[id].el         /item/ID
  _parts/card.el       a helper: loaded by the page, no route
api/                   one file per API address (server side)
  _store.el            a helper: loaded before the routes, no route
  items.el             /api/items
  items/[id].el        /api/items/ID
shared/                record types (nextel-defschema), loaded by both sides
lisp/                  your own page-side Lisp (optional), listed in index.html by you
vendor/elisp-next/     the project's copy of elisp-next: lisp/, bin/, LICENSE
.data/                 the server's data under serve-project.sh (not served)
```

<a id="file-names"></a>
### File names

A pattern is the file's path without `.el`; for api/ the path includes `api/`. Verified with `nextel-pattern-of-file`:

| File | Pattern | Parameters |
|---|---|---|
| `pages/index.el` | `/` | |
| `pages/blog/index.el` | `/blog` | |
| `pages/watch.el` | `/watch` | |
| `pages/channel/[id].el` | `/channel/[id]` | `:id`, one segment |
| `pages/docs/[...path].el` | `/docs/[...path]` | `:path`, a list of one segment or more; only as the last segment |
| `pages/About.el` | `/About` | case is kept; matching is case-sensitive |
| `api/feed/index.el` | `/api/feed` | |
| `api/later/[id].el` | `/api/later/[id]` | `:id` |

pages/:

- `_layout.el` (top level only) is the layout; it has to contain `(nextel-layout NAME`.
- `404.el` (top level only) is `:not-found` and has no route; it has to contain `(nextel-page NAME`. `pages/blog/404.el` is the ordinary route `/blog/404`.
- A file or directory whose name starts with `_` is a helper: the page loads it (after `_layout.el`), it is no route.
- A file or directory whose name starts with `.` is ignored (Emacs lock files `.#x.el`). Only `*.el` counts (`.elc` and `~` backups do not).
- Every other file has to contain the text `(nextel-page NAME`, or the writer fails: `pages/broken.el has no (nextel-page NAME ...)`.
- Two files of one pattern fail: `pages/news.el and pages/news/index.el are both /news`.
- `[[...name]]` (optional catch-all) and route groups `(name)` are not supported.

api/:

- A file or directory whose name starts with `_` is a helper, loaded before the routes in path order. Every other `*.el` is a route; it may handle any number of methods.
- The server skips hidden files and directories too (since v0.1.1; v0.1.0 loaded them, and an Emacs lock file stopped it from starting).
- Two files of one pattern (`api/things.el`, `api/things/index.el`) are not an error: both register, and for each method the first loaded (path order) wins.

shared/: every `*.el` below it, in path order (`shared/sub/a.el` before `shared/z.el`). Both sides load it, the page before your scripts and pages, the server before api/. A file of shared/ may use nextel-schema.el and Emacs only: not react.el (absent on the server) nor app-server.el (absent on the page). `(require 'nextel-schema)` at its top works on both sides.

<a id="index-html"></a>
### index.html

It needs the mount element (`<div id="app">`, the selector of [`nextel-mount-selector`](#nextel-mount-selector)), the two regions, and elisp-react's script after them:

```html
    <div id="app">Loading Emacs…</div>
    <!-- nextel:framework -->
    <!-- /nextel:framework -->
    <!-- nextel:pages -->
    <!-- /nextel:pages -->
    <script type="module" src="https://modeverv.github.io/elisp-react/js/elisp-react.js"></script>
```

- The opening marker may be anywhere; the closing one has to begin its line (spaces and tabs before it only). Both on one line fail: `index.html has no <!-- /nextel:framework -->`. A missing opening marker: `index.html has no <!-- nextel:framework --> ... <!-- /nextel:framework -->`.
- What is between a pair is replaced by a newline, one `    <script type="text/emacs-lisp" src="PATH"></script>` per file (four spaces), and a newline. The closing marker's line is kept.
- Your own `<script type="text/emacs-lisp">` tags go between `<!-- /nextel:framework -->` and `<!-- nextel:pages -->`: they load after elisp-next and shared/, before the pages.
- The `src` of a page with brackets is written as it is (`pages/item/[id].el`); serve-project.sh serves it both raw and as `%5Bid%5D`.

<a id="server-el"></a>
### server.el

```elisp
(declare-function nextel-server-load "nextel-server")
(load (expand-file-name "vendor/elisp-next/lisp/nextel-server.el" app-server-project-directory) nil t)
(nextel-server-load)
```

- serve-project.el byte-compiles server.el before loading it. Without the first line the compiler warns `the function ‘nextel-server-load’ is not known to be defined` at every start.
- `app-server-project-directory` is the project (native), or the tab's copy of its text files (elisp-studio).
- `nextel-server-load` makes `app-server-handle` an alias of `nextel-server-handle`: server.el must not define its own `app-server-handle`.

<a id="vendor"></a>
### vendor/elisp-next

The page loads elisp-next from the project (elisp-studio's preview loads nothing from other sites). In the project:

```sh
mkdir -p vendor/elisp-next
curl -L https://github.com/modeverv/elisp-next/archive/refs/tags/v0.1.2.tar.gz \
  | tar -xz --strip-components=1 -C vendor/elisp-next elisp-next-0.1.2/lisp elisp-next-0.1.2/bin elisp-next-0.1.2/LICENSE
```

The routes writer writes its own directory, relative to the project, into the framework region, so it has to be the copy inside the project (any directory inside works; `lib/next/lisp/` was tried). A copy outside fails: `nextel: load the copy of nextel-build.el that is in the project (vendor/elisp-next/lisp/), not DIRECTORY`.

## Pages

<a id="nextel-page"></a>
### `(nextel-page NAME &rest SPEC)` — macro

Defines the page component NAME (an unquoted symbol). SPEC is `react-define-component`'s plist with four more keys. Expansion:

```elisp
(nextel-page P :load L :head H :render R :initial-state I)
;; =>
(progn (put 'P 'nextel-page (list :load L :head H))
       (react-define-component 'P :render R :initial-state I))
```

| Key | Called with → returns | |
|---|---|---|
| `:load` | `(ROUTE)` → an awaitable | The page's data. [Below](#load). |
| `:loading` | `(ROUTE)` → an element | Shown while `:load` runs. Default [`nextel-loading-function`](#nextel-loading-function). |
| `:error` | `(ROUTE ERROR RETRY)` → an element | Shown after `:load` failed. Default [`nextel-error-function`](#nextel-error-function). |
| `:head` | `(ROUTE DATA)` → `(:title TEXT :description TEXT :meta ((NAME . CONTENT) ...))` | The document's title and `<meta>`. [Below](#head). |
| `:render` | `(SELF)` → an element | Required. |
| `:initial-state`, `:did-mount`, `:did-update`, `:will-unmount`, `:should-update`, `:pure`, `:did-catch` | as in [`react-define-component`](#from-elisp-react) | |

Evaluating it again (elisp-studio reloads a saved file) replaces both the component and its four keys; mounted instances render again with their state.

The props of a page (verified):

```elisp
(:key ItemPage
 :route (:page ItemPage :pattern "/item/[id]" :path "/item/a" :params (:id "a") :query nil)
 :data (:title "A")
 ;; then what nextel-page-props-function returns, appended: :extra 1 ...
 )
```

`:data` is nil for a page without `:load`. `:key` is the page's symbol, so between two addresses of the same page (`/p/1` → `/p/2`) the instance stays: `:initial-state` ran once and `:did-update` saw the new route (verified). A page with `:load` whose new data is not there yet is replaced by its `:loading` element meanwhile, so it mounts again.

What the router renders inside the layout:

| The page | Its data | Rendered |
|---|---|---|
| no `:load` | | `(PAGE PROPS)` |
| `:load` | loading, nothing yet | `:loading`, else `nextel-loading-function` |
| `:load` | failed | `:error`, else `nextel-error-function` |
| `:load` | loading again after a failure (Retry) | `:loading` |
| `:load` | there (also while `nextel-reload` loads it again) | `(PAGE PROPS)` with `:data` |
| no route matched, `nextel-not-found` nil | | `""` (the layout with nothing in it) |

<a id="load"></a>
#### `:load`

- Called with the route while the router renders, when the data of the key `(nextel PAGE PARAMS QUERY)` has not been loaded yet.
- Returns a function of `(RESOLVE REJECT)`: `nextel-request`, `react-fetch-async`, `react-sleep`, `react-all`, `react-race`, or your own lambda. **A `react-async` task is not one**: the router's render fails (`react-render-error`, `Invalid function: #s(react-task ...)`). Wrap it: `(react-race (list (react-async ...)))` works.
- What it resolves is `:data` (`(nextel-data SELF)`); what it rejects with is ERROR for `:error` (for `nextel-request`, `(:status N :message TEXT)`).
- The data is kept by key (`react-query`): back at an address with the same page, params and query, the page shows at once and nothing is loaded. Another query string is another key and loads again.
- Data older than [`nextel-stale-ms`](#nextel-stale-ms) (60 s) is loaded again when the router comes back to its address: in the background, the page showing the data it has meanwhile (no `:loading`), and `:load` called again. Rendering again at the same address loads nothing. After the source of the data changed, call [`nextel-reload`](#nextel-reload).

#### `:loading` and `:error`

- `:loading` is shown while the first load runs, and while it runs again after a failure.
- `:error` gets the route, the rejection value, and RETRY: `(funcall RETRY)` marks the key stale and loads it again (`:loading` meanwhile).
- Both are elements in place of the page, not the page component: the page has no instance or state yet.

<a id="head"></a>
#### `:head`

- Called at every render of the router while the page is shown: for a page with `:load` only once its data is there, with that data; for a page without `:load` always, with DATA nil.
- The title is `(funcall nextel-title-function TITLE)`. TITLE is nil when the page has no `:head`, while its data loads, or when `:head` returns nil; the default `nextel-title-function` makes that `""`.
- `<meta>`: `:description` becomes `("description" . TEXT)`, then each `(NAME . CONTENT)` of `:meta`, through `react-set-meta`. They are set only when the title or the metas changed, and **never removed**: an `og:url` that one page set stays on the next page that does not set it (verified; in Chrome, the example's `Item 1` description stayed on its 404 page). `react-set-meta` with a nil CONTENT removes one, so `:meta '(("og:url" . nil))` clears it (from react.el's documentation; not checked in a browser).

<a id="nextel-layout"></a>
### `(nextel-layout NAME &rest SPEC)` — macro

`(react-define-component 'NAME ,@SPEC)`, nothing more. The layout of pages/_layout.el is around every page and stays mounted from one page to the next. Its props are `(:route ROUTE :children (PAGE-ELEMENT))`: render the page with `(react-props self :children)`. One layout; no nested layouts. pages/_layout.el is a good place for the settings below (`setq` at load time), as Parens does.

<a id="nextel-loading-function"></a>
### `nextel-loading-function` — variable

`(lambda (_route) "")`. A function of ROUTE: the element shown while a page without `:loading` loads.

<a id="nextel-error-function"></a>
### `nextel-error-function` — variable

A function of `(ROUTE ERROR RETRY)`: the element shown when the `:load` of a page without `:error` failed. The default shows `(plist-get ERROR :message)`, or ERROR itself, and a Retry button:

```html
<div class="nextel-error"><p>bad</p><button type="button">Retry</button></div>
```

<a id="nextel-title-function"></a>
### `nextel-title-function` — variable

`(lambda (title) (or title ""))`. A function of TITLE (the `:head` title, or nil): the document's title. Parens: `(lambda (part) (if part (concat part " - Parens") "Parens"))`.

<a id="nextel-page-props-function"></a>
### `nextel-page-props-function` — variable

nil, or a function of ROUTE that returns a plist: props every page gets after `:key :route :data` (those three cannot be overridden). It is called when the page renders; after what it returns changed, call [`nextel-refresh`](#nextel-refresh) (verified: the new value reaches the page only then).

<a id="route-plist"></a>
### The route

A plist, the `:route` prop of the page and of the layout:

| Key | Value | Example (`#/item/a%20b?x=1&y=%E3%81%82&x=2`) |
|---|---|---|
| `:page` | the page symbol; `nextel-not-found` when no pattern matched | `Item` |
| `:pattern` | the matched pattern; nil when none matched | `"/item/[id]"` |
| `:path` | the path as in the address, not decoded | `"/item/a%20b"` |
| `:params` | a plist, keywords → decoded strings (a list of strings for `[...name]`); nil for a pattern without parameters | `(:id "a b")` |
| `:query` | an alist of decoded strings, in order, duplicates kept, `+` read as a space | `(("x" . "1") ("y" . "あ") ("x" . "2"))` |

A path with a trailing slash matches the pattern without it (`/watch/` is `/watch`). An empty path is `/`.

<a id="nextel-route"></a>
### `(nextel-route)` → route

The route the router rendered last; nil before it mounted.

<a id="nextel-param"></a>
### `(nextel-param THING KEY)` → string, list of strings, or nil

The parameter KEY (a keyword, `:id`) of THING, a route or a page instance (SELF; its `:route` prop is used).

<a id="nextel-query"></a>
### `(nextel-query THING NAME)` → string or nil

The first value of NAME in the query of THING (a route or a page instance). **NAME is a string** (`"v"`), not a keyword; the value is a string (`"30"`, not 30).

<a id="nextel-data"></a>
### `(nextel-data SELF)` → data

`(react-props SELF :data)`: what the page's `:load` resolved with.

<a id="nextel-define-routes"></a>
### `(nextel-define-routes ROUTES &rest OPTIONS)`

ROUTES is `((PATTERN . PAGE) ...)`; OPTIONS `:layout SYMBOL :not-found SYMBOL`. Sets [`nextel-routes`](#nextel-routes) (sorted by [`nextel-pattern<`](#nextel-pattern-lessp)), [`nextel-layout`](#nextel-layout-variable) and [`nextel-not-found`](#nextel-not-found). routes.el calls it; you do not.

<a id="nextel-start"></a>
### `(nextel-start SELECTOR)`

`(react-mount '(nextel-router) SELECTOR)`. routes.el calls it last, with [`nextel-mount-selector`](#nextel-mount-selector).

<a id="nextel-router"></a>
### `nextel-router` — component

Watches the address (`react-location-watch`), resolves it, renders `(LAYOUT (:route ROUTE) PAGE-ELEMENT)` or the page element alone, sets the title and metas, and runs [`nextel-navigate-functions`](#nextel-navigate-functions). One instance, mounted by `nextel-start`.

<a id="nextel-resolve"></a>
### `(nextel-resolve PATH &optional SEARCH)` → route

The route of PATH (`"/item/7"`) with the query string SEARCH (`"?t=30"`, with or without `?`), against `nextel-routes`, first match wins. `(nextel-resolve "/nowhere" "")` with `nextel-not-found` `NF` is `(:page NF :pattern nil :path "/nowhere" :params nil :query nil)`.

<a id="nextel-routes"></a>
### `nextel-routes`, <a id="nextel-layout-variable"></a>`nextel-layout`, <a id="nextel-not-found"></a>`nextel-not-found` — variables

What `nextel-define-routes` set: `((PATTERN . PAGE) ...)` in the order tried, the layout symbol or nil, the 404 page symbol or nil.

<a id="nextel-stale-ms"></a>
### `nextel-stale-ms` — variable

60000: how long, in milliseconds, a page's loaded data counts as fresh. When the router comes to an address (its page, params or query differ from the address it rendered last) whose data was loaded longer ago than that, it loads the data again in the background (`react-invalidate` of its key): the page keeps showing the data it has, then renders with the new data. nil: never because of age (only `nextel-reload` and a retry load again). The router keeps the time of each load itself: `react-query`'s own `:stale-ms` looks at age only when a component reads a key for the first time, and the router keeps reading every key it has read. (v0.1.0: no effect.)

## Addresses and navigation

<a id="nextel-href"></a>
### `(nextel-href PATTERN &rest PARAMS)` → string

The address of the page PATTERN, for a link: [`nextel-fill`](#nextel-fill) of PATTERN and PARAMS, after `#` (hash mode) or after `nextel-base-path` (path mode).

```elisp
(nextel-href "/item/[id]" :id "7" :t 30)   ; => "#/item/7?t=30"
(nextel-href "/")                          ; => "#/"
;; nextel-url-mode path, nextel-base-path "/app":
(nextel-href "/item/[id]" :id "7" :t 30)   ; => "/app/item/7?t=30"
(nextel-href "/")                          ; => "/app/"
```

PATTERN is the pattern (with its brackets), never a filled path: `(nextel-href "/item/[id]" :id id)`, not `(nextel-href (concat "/item/" id))`, which would not be encoded.

<a id="link"></a>
### `Link` — component

`(Link (:href HREF PROP...) CHILD...)`: an `<a>` with every prop but `:children` and `:key`. In hash mode the browser follows it. In path mode it also gets an `:on-click` that prevents the browser's navigation and calls `(nextel-navigate HREF)` (verified: a click tells the host `(:url "/app/" :replace nil)`). Rendered: `<a href="#/x" class="c">go</a>`. A plain `(a (:href (nextel-href ...)))` works too in hash mode; in path mode the browser would load the page anew.

<a id="nextel-navigate"></a>
### `(nextel-navigate HREF &optional REPLACE)`

`(react-navigate HREF REPLACE)`: a new history entry, or with REPLACE the current one replaced. Within the page's origin the page stays and the router hears the new address; another origin is loaded. HREF is what `nextel-href` returns.

<a id="nextel-go"></a>
### `(nextel-go PATTERN &rest PARAMS)`

`(nextel-navigate (nextel-href PATTERN PARAMS...))`. `(nextel-go "/item/[id]" :id "z" :t 3)` tells the host `(:url "#/item/z?t=3" :replace nil)`. No REPLACE: use `nextel-navigate` for that.

<a id="nextel-navigate-functions"></a>
### `nextel-navigate-functions` — variable

A list of functions of ROUTE, called by the router after it rendered an address whose path or query differs from the last one: also at the first render, and when only the query changed. For a page with `:load` they run once, at the render that shows `:loading`, not again when the data comes. The router calls them with `dolist` (the page's Emacs ran no hooks before wasmacs's fix of 2026-11-16); add with `add-hook` or `push`. Use: scroll to the top, close a drawer, count a page view.

<a id="nextel-refresh"></a>
### `(nextel-refresh)`

`(react-refresh 'nextel-router)`: render the router again, and with it the layout and the page, with what `nextel-page-props-function` says now. Loads nothing.

<a id="nextel-reload"></a>
### `(nextel-reload)`

`(react-invalidate '(nextel))`: every page's data is stale, and every key the router has read since it mounted is loaded again at once (the pages visited before too, each query string; verified: two loads after visiting `/item/a` and `/item/a?x=1`). The page shown keeps its data until the new data comes; a failure then shows `:error`. Call it after a request that changed what pages load.

<a id="nextel-url-mode"></a>
### `nextel-url-mode` — variable

`hash` (default) or `path`. See the [table](#mental-model). Set it before routes.el runs (in a script loaded earlier, or pages/_layout.el).

<a id="nextel-base-path"></a>
### `nextel-base-path` — variable

`""`. In path mode, the path under which the application is (`"/app"`, no trailing slash). It is put before every href and API URL and removed from the address before matching; an address not under it is matched whole.

In path mode the server has to answer every page address with index.html. serve-project.sh answers a path that is no file with 404, unless server.el sets `app-server-page-function`; with `(setq app-server-page-function (lambda (_path) (list :status 200)))` it sends index.html for `/item/1` (verified with curl). index.html's script `src`s are relative, so at `/item/1` a browser resolves them under `/item/`: give such a page `<base href="/">` (or the base path) or absolute `src`s (inferred from HTML's rules; not tried in a browser). The API URL is `BASE/api/...`; serve-project.sh sends only paths that start with `/api/` to server.el.

## Patterns

nextel-route.el; the page, the server and the writer use the same functions.

<a id="nextel-pattern-of-file"></a>
### `(nextel-pattern-of-file FILE)` → pattern

FILE relative to pages/, or to the project for api/: `"index.el"` → `"/"`, `"blog/[slug].el"` → `"/blog/[slug]"`, `"api/feed/index.el"` → `"/api/feed"`.

<a id="nextel-match"></a>
### `(nextel-match PATTERN PATH)` → plist, t or nil

| Call | Result |
|---|---|
| `(nextel-match "/" "/")` | `t` (matches, no parameters) |
| `(nextel-match "/watch" "/watch/")` | `t` |
| `(nextel-match "/watch" "/Watch")` | `nil` |
| `(nextel-match "/channel/[id]" "/channel/UC%E3%81%82")` | `(:id "UCあ")` (decoded as UTF-8) |
| `(nextel-match "/x/[id]" "/x/a%2Fb")` | `(:id "a/b")` |
| `(nextel-match "/channel/[id]" "/channel/a/b")` | `nil` |
| `(nextel-match "/docs/[...path]" "/docs/a/b")` | `(:path ("a" "b"))` |
| `(nextel-match "/docs/[...path]" "/docs")` | `nil` (one segment at least) |
| `(nextel-match "/docs/[...path]/edit" "/docs/a/edit")` | `nil` (`[...]` only last) |
| `(nextel-match "/café" "/caf%C3%A9")` | `t` (fixed segments are compared decoded) |

<a id="nextel-pattern-rank"></a>
### `(nextel-pattern-rank PATTERN)` → list

One number per segment: 0 fixed, 1 `[name]`, 2 `[...name]`. `"/docs/[id]/[...rest]"` → `(0 1 2)`.

<a id="nextel-pattern-lessp"></a>
### `(nextel-pattern< A B)` → boolean

Non-nil if A is tried before B: compare ranks segment by segment (fixed before parameter before catch-all); of two that agree as far as both go, the longer first; else alphabetical. `(sort (list "/" "/a" "/[x]" "/a/b" "/a/[y]" "/[...all]" "/b") #'nextel-pattern<)` → `("/a/b" "/a/[y]" "/a" "/b" "/[x]" "/[...all]" "/")`. So `/item/new` beats `/item/[id]`.

<a id="nextel-fill"></a>
### `(nextel-fill PATTERN PARAMS)` → string

PATTERN with each `[name]` taken from the plist PARAMS, and the other non-nil PARAMS as a query string in their order. Each value: a string as is, a number by `number-to-string`, a symbol by its name (`t` → `t`, `:kw` → `:kw`), anything else by `format "%s"`; then `url-hexify-string` (UTF-8; only `A-Z a-z 0-9 - _ . ~` stay). A list for a `[name]` is joined with `/`, each part encoded (for `[...name]`).

| Call | Result |
|---|---|
| `(nextel-fill "/x/[id]" '(:id "a/b c"))` | `"/x/a%2Fb%20c"` |
| `(nextel-fill "/x/[id]" '(:id "あ"))` | `"/x/%E3%81%82"` |
| `(nextel-fill "/x/[id]" '(:id 42))` | `"/x/42"` |
| `(nextel-fill "/x/[id]" '(:id ("a" "b")))` | `"/x/a/b"` |
| `(nextel-fill "/x" '(:q "a b&c=d" :n 0 :s "" :b t :k :kw :l (1 2) :z nil))` | `"/x?q=a%20b%26c%3Dd&n=0&s=&b=t&k=%3Akw&l=%281%202%29"` |
| `(nextel-fill "/x" '(:a 1 :a 2))` | `"/x?a=1&a=2"` |
| `(nextel-fill "/x/[id]" '(:id ""))` | `"/x/"` (which `/x/[id]` does not match) |
| `(nextel-fill "/x/[id]" '(:id nil))` | error `/x/[id] needs :id` |

## Requests

<a id="nextel-request"></a>
### `(nextel-request METHOD PATTERN &rest OPTIONS)` → awaitable

What the API route PATTERN (`"/api/items/[id]"`) answers to METHOD (`"GET"`, `"POST"`, ...; sent as given). OPTIONS:

| Option | |
|---|---|
| `:KEY VALUE` | Fills `[key]` of PATTERN; the others form the query string ([`nextel-fill`](#nextel-fill)'s rules). |
| `:body DATA` | Sent as `(prin1-to-string DATA)` with `print-length` and `print-level` nil. With `:body nil` the body is `"nil"`; without `:body` there is none. |
| `:sends TYPE` | DATA is checked when `nextel-request` is called: if wrong, it signals `nextel-type-error` at once (`POST /api/items body.id is required`) and nothing is sent. |
| `:returns TYPE` | The answer is checked; a wrong one fails the request. |

`:body`, `:sends` and `:returns` cannot be query parameters. No header is set (no Content-Type). The URL is `api/...` relative to the document in hash mode, `BASE/api/...` in path mode: `(nextel-request "POST" "/api/items/[id]" :id "a b" :q "x")` fetches `api/items/a%20b?q=x`.

The value is a function of `(RESOLVE REJECT)`; nothing is sent until it is called: by `react-await` in `react-async`, as a page's `:load`, or by `funcall`. Then:

| The response | Outcome |
|---|---|
| 2xx, text read as Lisp (`read-from-string`, its first datum) | resolves with it, checked against `:returns` |
| 2xx, text not readable (`""`) | resolves with nil (fails if `:returns` refuses nil) |
| 2xx, not of `:returns` | rejects `(:status nil :message "GET /api/items/[id].count: expected integer, got \"3\"")` |
| not 2xx | rejects `(:status 404 :message "No such item")`: the message is the body if it reads as a string, else `"HTTP 404"` |
| no response (network) | rejects `(:status nil :message TEXT)`, TEXT being what the host's fetch said (`react-fetch`'s `:catch`) |

So `:status` is nil when the answer came but was not of `:returns`, or no answer came.

Catching both kinds of failure in `react-async` (from the [worked example](#worked-example)):

```elisp
(react-async
  (condition-case failure
      (progn
        (react-await (nextel-request "POST" "/api/items"
                                     :body (list :title (and (not (string-empty-p title)) title))
                                     :sends 'demo-new-item
                                     :returns 'demo-item))
        (nextel-reload))
    ;; :sends failed: signalled at once, nothing was sent.
    (nextel-type-error (react-set-state self :problem (cadr failure)))
    ;; The server refused, or its answer was not a demo-item.
    (react-async-error (react-set-state self :problem (plist-get (cadr failure) :message)))))
```

A rejection reaches `react-await` as the error `(react-async-error (:status 404 :message "No such API: /api/x"))`: the plist is `(cadr failure)`.

**The wire format** is printed Lisp data, not JSON, both ways. A record is a plist and travels as one: `(:id "1" :title "Milk")`. serve-project.sh answers with `Content-Type: application/x-emacs-lisp; charset=utf-8`; an error's body is a printed string, `"No such item"` with its quotes.

## Schemas

nextel-schema.el, loaded by both sides; shared/ holds the definitions.

<a id="nextel-defschema"></a>
### `(nextel-defschema NAME [DOC] FIELD...)` — macro

```text
FIELD := (FIELD-NAME TYPE)
       | (FIELD-NAME TYPE :required t)
TYPE  := string | integer | number | boolean | symbol | keyword | any
       | SCHEMA-NAME
       | (member VALUE...) | (list-of TYPE) | (vector-of TYPE) | (or TYPE...)
```

| Type | Accepts |
|---|---|
| `string` | `stringp` |
| `integer` | `integerp` (1.5 is not) |
| `number` | `numberp` |
| `boolean` | `t` or `nil` |
| `symbol` | `symbolp` (keywords too) |
| `keyword` | `keywordp` |
| `any` | anything |
| a schema's name | a plist of that schema (below) |
| `(member VALUE...)` | a value `equal` to one of them: `(member live upcoming)`, `(member t :false)` |
| `(list-of TYPE)` | a list whose every element is of TYPE |
| `(vector-of TYPE)` | a vector whose every element is of TYPE |
| `(or TYPE...)` | a value of one of the types |

A value of a schema: a list of even length; every key a keyword naming a field (else `no field :nick in p-person`); every field whose value is non-nil is of its type; every `:required` field non-nil. **nil means absent**: a field may be left out or nil; a `:required` field may not be nil; a `boolean` field is false when absent. Order of keys does not matter. A schema may name a schema defined later: types are looked up when a value is checked.

`(nextel-defschema demo-item "An item of the list." (id string :required t) (title string :required t) (done boolean))` (the [example's](#worked-example)) defines, and returns `demo-item`:

| Defined | What it does |
|---|---|
| `(make-demo-item &rest FIELDS)` | `(nextel-check 'demo-item FIELDS)`: the plist as given, or `nextel-type-error`. No defaults, no reordering. |
| `(demo-item-p VALUE)` | `(nextel-type-p 'demo-item VALUE)` |
| `(demo-item-id RECORD)`, `demo-item-title`, `demo-item-done` | `defsubst`s: `(plist-get RECORD :id)`, ... |

These are global function names: a field `by-id` of `demo-item` would define `demo-item-by-id` over any function of yours with that name, and yours over it. A malformed field fails at expansion: `nextel-defschema bad: a field is (NAME TYPE [:required t]), not (id)`. Defining the same NAME again replaces it.

<a id="nextel-check"></a>
### `(nextel-check TYPE VALUE &optional WHERE)` → VALUE

VALUE if it is of TYPE, else signals `nextel-type-error` whose data is one string, `WHERE: expected TYPE, got VALUE`, `WHERE is required` or `WHERE: no field KEY in SCHEMA`. WHERE defaults to the type's name; a field adds `.FIELD`, an element `[INDEX]`. VALUE is printed with `print-length` 4 and `print-level` 2. Verified messages, with the schema `p-item` (fields `id` required, `count` integer, `tags` `(list-of string)`, `vec` `(vector-of integer)`, `kind` `(member book film)`, `either` `(or integer string)`, `owner` `p-person`, `people` `(list-of p-person)`) and `p-person` (`name` string, required):

| VALUE (TYPE `p-item` unless said) | Message |
|---|---|
| `(:count 2)` | `p-item.id is required` |
| `(:id nil)` | `p-item.id is required` |
| `(:id "a" :count 1.5)` | `p-item.count: expected integer, got 1.5` |
| `(:id "a" :tags ("x" 3))` | `p-item.tags[1]: expected string, got 3` |
| `(:id "a" :vec [1 "2"])` | `p-item.vec[1]: expected integer, got "2"` |
| `(:id "a" :vec (1 2))` | `p-item.vec: expected (vector-of integer), got (1 2)` |
| `(:id "a" :kind song)` | `p-item.kind: expected (member book film), got song` |
| `(:id "a" :either sym)` | `p-item.either: expected (or integer string), got sym` |
| `(:id "a" :owner (:nick "n"))` | `p-item.owner: no field :nick in p-person` |
| `(:id "a" :people ((:name "a") (:name 2)))` | `p-item.people[1].name: expected string, got 2` |
| `(id "a")` | `p-item: no field id in p-item` |
| `(:id "a" :count)` | `p-item: expected p-item, got (:id "a" :count)` |
| `"a"` | `p-item: expected p-item, got "a"` |
| `((:id "a") (:id 2))`, TYPE `(list-of p-item)` | `(list-of p-item)[1].id: expected string, got 2` |
| `3`, TYPE `string`, WHERE `"title"` | `title: expected string, got 3` |

The WHERE that elisp-next passes: `"body"` for `:accepts` on the server (`body.title is required`), `"METHOD PATTERN"` for `:returns` (`GET /api/items/[id].count: ...`), `"METHOD PATTERN body"` for `:sends` (`POST /api/items body.id is required`).

A TYPE that is neither a type nor a schema is a plain `error`, not `nextel-type-error`: `No type or schema named unknown-type`, `Not a type: (frob x)`.

<a id="nextel-type-p"></a>
### `(nextel-type-p TYPE VALUE)` → t or nil

Catches `nextel-type-error` only: an unknown TYPE still signals `No type or schema named ...`.

<a id="nextel-schema-fields"></a>
### `(nextel-schema-fields NAME)` → fields or nil

`((FIELD TYPE :required BOOL) ...)`: `(nextel-schema-fields 'p-person)` → `((name string :required t))`; nil for an unknown name.

<a id="nextel-type-error"></a>
### `nextel-type-error` — error symbol

Conditions `(nextel-type-error error)`, message `"Not of the expected type"`. Data: `(MESSAGE)`. Show `(cadr ERR)`; `error-message-string` gives `Not of the expected type: "string: expected string, got 3"`.

## Server

nextel-server.el, under elisp-studio's app-server.el.

<a id="nextel-server-load"></a>
### `(nextel-server-load &optional DIRECTORY)` → routes

DIRECTORY defaults to `app-server-project-directory` (else `default-directory`). It:

1. loads every `*.el` of `DIRECTORY/shared/` in path order (if the directory exists), leaving out hidden files and directories (names that start with `.`), as in the steps below;
2. empties [`nextel-server-routes`](#nextel-server-routes);
3. loads the helpers of api/ (a path component starting with `_`) in path order;
4. notes every other `*.el` of api/ with its pattern (from the file name, `nextel-pattern-of-file`), most specific first;
5. unless loading is lazy (below), loads each of those files with its pattern current, so that its `nextel-handle` calls register under it, and sorts the routes by pattern (`nextel-pattern<`; methods of a file in the order written);
6. makes `app-server-handle` an alias of `nextel-server-handle`;
7. returns `nextel-server-routes`: every route, or nil when loading is lazy.

A file is loaded from its `.elc` when that is newer than the file (elisp-studio's `server/cgi/install.sh` compiles shared/ and api/ where it deploys; nothing else writes them).

**Lazy loading.** When [`nextel-server-lazy`](#nextel-server-lazy) or elisp-studio's `app-server-single-request` is non-nil (its `serve-cgi.el` sets the latter: a CGI starts one Emacs per request), step 5 is left out: `nextel-server-handle` loads the file that answers a request when the request comes, and no other file of api/. The answers are the same, 404 and 405 included. What a request needs from elsewhere belongs in shared/ or a helper, which are always loaded. Measured on Sakura's rental server (Emacs 27.2) with Parens, 4 route files: a request takes 7 ms in Emacs once elisp-next, `shared/` and `api/` are compiled. With so few small files loading all of them costs about as much as loading one (within 1 ms); lazy loading matters as `api/` grows, and the compiled files matter at once (nextel-schema.el and nextel-route.el: 2.3 ms from source, 0.3 ms compiled).

The server reads the directory itself (routes.el is not used): a new or renamed api/ file is a route when `nextel-server-load` runs again, i.e. at the next start of the server. elisp-studio's `--native-server` restarts it when a file it loaded is saved; with serve-project.sh, restart it.

<a id="nextel-handle"></a>
### `(nextel-handle METHOD &rest SPEC)` → nil

In a file of api/ only (else `nextel-handle belongs in a file of api/, loaded by ‘nextel-server-load’`). METHOD is an upper-case string compared with `equal` (`"GET"`, `"POST"`, `"PUT"`, `"PATCH"`, `"DELETE"`; HEAD is not derived from GET). SPEC:

| Key | |
|---|---|
| `:handler` | Required (`GET /api/broken has no :handler`). A function of REQUEST. |
| `:accepts TYPE` | The body is checked first; a wrong one is answered 400 with the message, and the handler does not run. An empty body is nil, which is checked too. |
| `:returns TYPE` | The answer is checked; a wrong one is answered 500 `The server's answer is wrong: MESSAGE` and logged `nextel-server: GET /api/x answered wrongly: MESSAGE`. An answer of `app-server-defer` is checked when it comes. |

REQUEST is `(:method "GET" :path "/api/items/1" :params (:id "1") :body DATA)`: `:path` without the query string (a trailing slash kept), `:params` nil for a pattern without parameters, `:body` the data read by `app-server-data`. The query is `(app-server-parameter "q")`.

The handler returns: Lisp data (sent printed, 200); `(app-server-defer (lambda (respond fail) ...))` to answer later; or it signals: `(app-server-refuse MESSAGE [STATUS])` (STATUS default 400), `error`, or anything else (see the table). Two `nextel-handle` of one method in one file: the first wins.

<a id="nextel-server-handle"></a>
### `(nextel-server-handle METHOD PATH BODY)`

What `app-server-handle` is after `nextel-server-load`. It tries the noted files in order (most specific first), loading each that matches PATH if it is not loaded, and the first whose pattern has a route answers. The most specific pattern that matches PATH answers (the first in the tried order; routes of two files of that one pattern count together), and a METHOD that it does not handle is 405, also when a less specific file would: `DELETE /api/things/new`, with `api/things/new.el` handling only GET, is 405 even if `api/things/[id].el` handles DELETE. (v0.1.0 went on to the next matching file.) Answers (verified, the text as sent):

| Case | Status | Body |
|---|---|---|
| The handler's answer | 200 | `(:id "1" :title "Milk")` |
| No pattern matches | 404 | `"No such API: /api/nothing"` |
| The most specific matching pattern has no METHOD | 405 | `"DELETE is not allowed at /api/items"` |
| BODY is not Lisp data | 400 | `"The request is not Lisp data"` |
| BODY names a symbol the server's Emacs does not know | 400 | `"The request names something unknown: :surprise"` |
| BODY not of `:accepts` | 400 | `"body.title: expected string, got 3"` |
| `(app-server-refuse "No such item" 404)` | 404 | `"No such item"` |
| The handler signals `error` | 400 | `"Something went wrong: 42"` |
| It signals another error | 400 | its message; `"The request could not be answered"` when `app-server-explain-errors` is nil, as under serve-project.sh |
| Answer not of `:returns` | 500 | `"The server's answer is wrong: GET /api/x.id: expected string, got 1"` |
| Deferred, `(funcall fail "busy" 503)` | 503 | `"busy"` |
| Deferred, never answered (native server) | 504 after `app-server-deferred-timeout` (30 s) | `"The server did not answer in time"` (read in app-server.el, not run) |

Text after the first datum of BODY is ignored. A body may contain only strings, numbers, lists, vectors and symbols the server already knows: the names that its loaded Lisp uses (schema keywords and `member` values are), nil and t.

<a id="nextel-server-routes"></a>
### `nextel-server-routes` — variable

`((PATTERN METHOD . SPEC) ...)` in the order tried; SPEC is the plist given to `nextel-handle`. With lazy loading it has the routes of the files loaded so far.

<a id="nextel-server-lazy"></a>
### `nextel-server-lazy` — variable

nil by default: every file of api/ is loaded at the start, so that a mistake in one shows when the server starts (in the studio, when it is saved). Non-nil: as `app-server-single-request` (above). Set it before `nextel-server-load`.

<a id="running-the-server"></a>
### Running it

```sh
../elisp-studio/tools/serve-project.sh DIRECTORY PORT     # PORT defaults to 8018
```

A native Emacs serves DIRECTORY's files on 127.0.0.1:PORT and sends paths starting with `/api/` to server.el (byte-compiled into `.data/server.elc`). `app-server-read` and `app-server-write` keep their files in `DIRECTORY/.data/`. It does not serve server.el, `*.sh` or names starting with `.`. A request whose `Origin` is another site gets 403 `"requests from other sites are refused"`; one with the page's own origin, or with none (curl), is answered. A downloaded elisp-studio project has `./run.sh [PORT]` for the same. Stop it with Ctrl-C (or kill the Emacs process).

## Routes writer

nextel-build.el, in the Emacs you edit with, elisp-studio's, or one in batch.

<a id="nextel-write-routes"></a>
### `M-x nextel-write-routes`, `(nextel-write-routes &optional ROOT)` → changed files

```text
M-x load-file RET vendor/elisp-next/lisp/nextel-build.el RET   once per session (the project's copy)
M-x nextel-write-routes                                        after adding, removing or renaming a page
```

ROOT defaults to the project of the current buffer's file (or `default-directory`); outside one: user error `Not in a project with index.html and pages/`. It computes routes.el and index.html and writes each only if its text changed: through the buffer that visits it if there is one (and saves it), which fails if that buffer has unsaved changes (`index.html has changes that are not saved: save it, then write the routes`). Returns the files written, relative (`("routes.el" "index.html")`, or nil), and says `nextel: 2 pages, 2 API routes: wrote routes.el, index.html` or `nextel: 2 pages, 2 API routes, nothing changed` (404.el and the layout are not counted as pages).

When to run it: after adding, removing or renaming a file of pages/ or shared/, after changing the NAME in a page's `(nextel-page NAME` or the layout's, and after adding or removing an api/ file (only routes.el's comment changes; `--check` notices).

<a id="nextel-routes-mode"></a>
### `M-x nextel-routes-mode` — global minor mode

Lighter ` nextel`, group `nextel`, hook `nextel-routes-mode-hook`. While on, every save of a file under `pages/`, `api/` or `shared/` of a project writes the routes; a failure is a message (`nextel: ...`), not an error. A file deleted or renamed without a save (dired, the shell) needs `M-x nextel-write-routes`.

<a id="bin-nextel-routes"></a>
### `bin/nextel-routes`

```sh
vendor/elisp-next/bin/nextel-routes [DIRECTORY]           # write routes.el and index.html's scripts
vendor/elisp-next/bin/nextel-routes --check [DIRECTORY]   # exit 1 when they are not up to date
vendor/elisp-next/bin/nextel-routes --watch [DIRECTORY]   # write them whenever pages/, api/ or shared/ change
```

It `cd`s to DIRECTORY (default `.`; a subdirectory of the project works) and runs `emacs --batch -Q -l BIN/../lisp/nextel-build.el -f COMMAND`, so run the project's copy. Emacs: `$EMACS`, else the first of `emacs` on PATH, `/Applications/Emacs.app/...`, `/Applications/Emacs-takaxp/Emacs.app/...` that starts. The flag must come first. Exit status: 0 done; 1 `--check` found them stale (`nextel: not up to date: routes.el, index.html; write them (M-x nextel-write-routes, bin/nextel-routes)`); 2 unknown flag (`usage: nextel-routes [--check | --watch] [DIRECTORY]`); 127 no Emacs; 255 a Lisp error (message and backtrace on stderr). In npm: `"routes": "vendor/elisp-next/bin/nextel-routes"`.

<a id="nextel-check-routes"></a>
### `(nextel-check-routes)` → boolean

For batch: the project of `default-directory`; prints `nextel: the routes are up to date` or the stale files, and in batch exits 0 or 1.

<a id="nextel-watch-routes"></a>
### `(nextel-watch-routes)`

For batch, never returns: every 0.5 s it compares the `*.el` files of pages/, api/ and shared/ (names and modification times, hidden ones left out) with the last time, and on a change calls `nextel-write-routes`. Errors are printed (`nextel: pages/broken.el has no (nextel-page NAME ...)`) and it goes on. Verified: a new page was in routes.el within a second. Stop it with Ctrl-C.

<a id="nextel-project-root"></a>
### `(nextel-project-root &optional FILE)` → directory or nil

The nearest directory at or above FILE (or `default-directory`) that has `index.html` and `pages/`, with a trailing slash.

<a id="nextel-read-project"></a>
### `(nextel-read-project ROOT)` → plist

What the writer works from. For a project with `pages/{_layout,_a,About,index,quoted}.el`, `pages/_drafts/x.el`, `pages/blog/{index,404}.el`, `api/{_x,x}.el`, `shared/{z,sub/a}.el`:

```elisp
(:routes (("/blog/404" "Blog404" "blog/404.el") ("/About" "Upper" "About.el") ("/blog" "BlogIndex" "blog/index.el")
          ("/quoted" "'Quoted" "quoted.el") ("/" "Wrong" "index.el"))
 :layout "Frame" :not-found nil
 :api (("/api/x" "api/x.el"))
 :shared ("shared/sub/a.el" "shared/z.el")
 :page-scripts ("pages/_layout.el" "pages/_a.el" "pages/_drafts/x.el" "pages/About.el" "pages/blog/404.el"
                "pages/blog/index.el" "pages/index.el" "pages/quoted.el"))
```

(`"Wrong"`: pages/index.el had `;; Like (nextel-page Wrong ...)` in a comment before its real form; `"'Quoted"`: pages/quoted.el said `(nextel-page 'Quoted`. Both are mistakes; see [pitfall 5](#pitfalls).)

<a id="nextel-routes-text"></a>
### `(nextel-routes-text PROJECT)` → string

The text of routes.el for PROJECT (`nextel-read-project`'s plist); exactly the [example's routes.el](#example-routes).

<a id="nextel-index-text"></a>
### `(nextel-index-text HTML PROJECT ROOT)` → string

HTML (index.html's text) with both regions filled as [described](#index-html).

<a id="nextel-mount-selector"></a>
### `nextel-mount-selector` — variable

`"#app"`: the argument of `nextel-start` in routes.el.

<a id="nextel-routes-file"></a>
### `nextel-routes-file` — variable

`"routes.el"`: the file the writer writes, relative to the project; also the last script of the pages region.

<a id="nextel-group"></a>
### `nextel` — custom group

Under `tools`; holds `nextel-routes-mode`.

<a id="from-elisp-react"></a>
## From elisp-react and app-server.el

The functions an elisp-next application uses besides elisp-next's own. Full references: [elisp-react's README](https://github.com/modeverv/elisp-react#api), [elisp-studio's README](https://github.com/modeverv/elisp-studio#a-server-side) and the docstrings of `lisp/react.el` and `lisp/app-server.el`.

Page side (react.el):

| | |
|---|---|
| `(react-define-component NAME &rest SPEC)` | `:render (SELF)` required; `:initial-state (PROPS)` → state plist; `:did-mount (SELF)`; `:did-update (SELF PREVIOUS-PROPS PREVIOUS-STATE)`; `:will-unmount (SELF)`; `:should-update (SELF PREVIOUS-PROPS PREVIOUS-STATE)` → nil skips; `:pure t`; `:did-catch (SELF ERROR)`. |
| `(jsx FORM)` | Markup without backquote: `(TAG PROPS CHILD...)` or `(TAG CHILD...)`, PROPS a list starting with a keyword. A list starting with an HTML tag, `<>`, or a **Capitalized** symbol is an element; anything else is evaluated Lisp (markup inside it needs `jsx` again). |
| `(react-props SELF &optional KEY)`, `(react-state SELF &optional KEY)`, `(react-set-state SELF &rest CHANGES)` | Props, state, change state and render again. |
| `(react-effect SELF KEY DEPS FUNCTION)` | In a render: run FUNCTION after it when DEPS changed; a function it returns cleans up. |
| `(react-async BODY...)` → task, `(react-await AWAITABLE)` | Async code; a failure signals `react-async-error` whose `cadr` is the rejection value. No `react-await` inside a `lambda`, `mapcar`, `with-temp-buffer` and the like. |
| `(react-fetch-async URL &rest OPTIONS)` | An awaitable whose value is the response `(:status :ok :url :redirected :headers :text)`. |
| `(react-all LIST)`, `(react-race LIST)`, `(react-sleep MS)` | Awaitables (functions of RESOLVE and REJECT); the first two also take tasks. |
| `(react-handler FUNCTION :prevent t ...)` | A listener prop with `preventDefault`, keys, throttling. |
| `(react-location &optional PART)`, `(react-navigate URL &optional REPLACE)`, `(react-history-go DELTA)` | The address; going somewhere. |
| `(react-set-title TEXT)`, `(react-set-meta NAME CONTENT)` | What `:head` uses. |
| `(react-query SELF KEY LOADER &rest OPTIONS)`, `(react-invalidate PREFIX)`, `(react-query-set KEY DATA)` | The cache under `:load`; its keys are `(nextel PAGE PARAMS QUERY)`. |
| `(react-storage-get KEY &optional DEFAULT)`, `(react-storage-set KEY VALUE)` | localStorage, any printable Lisp data. |

Server side (app-server.el):

| | |
|---|---|
| `app-server-project-directory` | The project's directory (server.el loads from it; it is on `load-path`). |
| `app-server-data-directory` | Where `app-server-write` keeps files (`.data/` under serve-project.sh). |
| `(app-server-read NAME &optional DEFAULT)`, `(app-server-write NAME VALUE)` | A Lisp value in `DATA/NAME.eld` (NAME of `A-Za-z0-9_-`); write replaces the file in one step and returns VALUE. |
| `(app-server-database &optional NAME)` | An SQLite database, for `sqlite-execute` and `sqlite-select`. |
| `(app-server-data TEXT &optional DEFAULT)` | The body read as data, never evaluated (nextel-server-handle calls it). |
| `(app-server-parameter NAME &optional DEFAULT)` | `?NAME=VALUE` of the request being answered. |
| `(app-server-refuse MESSAGE &optional STATUS)` | Answer with an error status (400 by default). |
| `(app-server-defer FUNCTION)` | Return it to answer later: FUNCTION gets RESPOND (data) and FAIL (message, status). |
| `(app-server-fetch URL &rest OPTIONS)`, `(app-server-after SECONDS FUNCTION)` | What a deferred answer waits for. |
| `app-server-explain-errors` | t: an error's text is the answer; nil under serve-project.sh. |
| `(app-server-respond METHOD PATH BODY &optional LATER HEADERS)` → `[STATUS TEXT HEADERS]` or nil | One request, as the hosts make it; for tests. |
| `app-server-page-function` | nil, or a function of PATH: serve-project.sh sends index.html for a path that is no file when it returns a plist. Needed for `path` mode; elisp-next does not use it. |

<a id="testing"></a>
## Testing an application

Both sides run in one native Emacs (`emacs --batch`), as elisp-next's own `test/nextel-test.el` does. The [example's test](#example-test):

- loads app-server.el, sets `app-server-data-directory` to a temporary directory, calls `(app-server-use-project ROOT)` and loads server.el, as serve-project.el does;
- calls the server with `(app-server-respond METHOD PATH BODY nil)` → `[STATUS TEXT HEADERS]`;
- starts the page with `react-testing-reset`, `(react-testing-location "#/")`, then `load`s the `src` of every `<script type="text/emacs-lisp">` of index.html in order (routes.el mounts the application), then `react-testing-flush`;
- answers the page's fetches with the server's answers (`react-testing-requests`, `react-testing-answer-fetch STATUS TEXT`): the whole round trip, types checked at both ends;
- moves with `(react-testing-location "#/item/1")`, looks with `react-testing-find`, `react-testing-text`, `react-testing-html`, acts with `react-testing-input` and `react-testing-click`, and reads the title and metas from `react-testing-told` (`("title" (:text "Milk - Demo"))`, `("meta" (:name "description" :content "Item 1"))`).

`react-testing-time-passes` fires timers (`react-set-timeout`, `react-sleep`).

<a id="pitfalls"></a>
## Rules and pitfalls

1. **The prefix is `nextel-`**, not `next-` (`next-line`, `next-match` are Emacs's). Your own code takes a prefix of its own (`demo-`).
2. **Every file starts with `-*- lexical-binding: t; -*-`.** Emacs 31 warns about a file without it (`Missing ‘lexical-binding’ cookie`) and evaluates it with dynamic binding.
3. **Write the routes after adding, removing or renaming a page or a shared/ file**, or after changing a component's NAME: `M-x nextel-write-routes`, `nextel-routes-mode`, or `bin/nextel-routes`. A page missing from routes.el has no address; a shared/ file missing from index.html is not loaded by the page. CI: `bin/nextel-routes --check`.
4. **routes.el names components.** After renaming `(nextel-page OldName` to `NewName` without writing the routes, the router renders an unknown element: `react: OldName is not a defined component; it is rendered as an unknown element <oldname> (a misspelled name, or a file loaded too late?)`, and `<OldName route="...">` in the page.
5. **The writer reads NAME as text**: the first `(nextel-page ` (or `(nextel-layout `) followed by a name anywhere in the file, a comment or string included. Write NAME unquoted (`(nextel-page 'Foo` puts `'Foo` into routes.el). Keep the form first and do not mention it in comments above it.
6. **Capitalize component names** (`HomePage`, `Layout`): `jsx` treats only Capitalized symbols, HTML tags and `<>` as elements. The router itself takes any symbol.
7. **Schema functions share your namespace.** `nextel-defschema demo-item` defines `make-demo-item`, `demo-item-p` and `demo-item-FIELD` for every field; a function of yours with such a name is replaced, or replaces the accessor, silently (the byte compiler may notice an argument count). Name helpers outside the prefix: `demo-find-item`, not `demo-item-by-id`.
8. **nil is absent.** A `:required` field cannot be nil; `boolean` false is the field left out; `(member nil ...)` cannot be told from absence.
9. **Keywords in, strings out.** `nextel-href`, `nextel-go`, `nextel-request` and `nextel-param` take keywords (`:id`, `:v`); `nextel-query` takes a string (`"v"`). Parameters and query values come back as strings: `(string-to-number (nextel-query self "t"))`.
10. **`:load` returns a function of RESOLVE and REJECT**, not a `react-async` task (the router fails); wrap a task in `(react-race (list TASK))`.
11. **Data is cached by page, params and query.** A new query string loads again; a revisit loads again in the background only when the data is older than `nextel-stale-ms` (60 s). After a request that changed data, call `nextel-reload` (it reloads every page visited).
12. **`<meta>` set by `:head` stay** on later pages that do not set them.
13. **`:body`, `:sends`, `:returns` are not query parameters** of `nextel-request`; every other keyword is.
14. **A `:sends` failure is signalled at once** (`nextel-type-error`, message in `(cadr err)`); a server or `:returns` failure arrives through the awaitable (`react-async-error`, plist in `(cadr err)`). Catch both where a user's input is sent.
15. **server.el keeps its `declare-function` line** (else a compiler warning at every start) and defines no `app-server-handle`.
16. **The framework comes from the project's copy** (`vendor/elisp-next/`): load that nextel-build.el, run that `bin/nextel-routes`. In one Emacs session the writer works from the copy loaded last: for another project, `M-x load-file` that project's copy.
17. **Hidden files are not loaded.** The server and the writer leave out every file and directory whose name starts with `.` (an Emacs lock file, `api/.#items.el`, while a buffer has unsaved changes). Under v0.1.0 the server loaded them, and a lock file stopped it from starting.
18. **A new api/ file is a route at the next start** of the server, not before. Two api/ files of one pattern are not an error; the first wins.
19. **What the page sends must be data the server knows.** A symbol the server's Emacs has never read is refused (400 `The request names something unknown: ...`) before `:accepts`: fine for keywords of shared/ schemas and `member` values, not for free `symbol` or `any` fields.
20. **Errors in a handler are 400, not 500,** and under serve-project.sh their text is hidden unless they are `error` or `user-error` (`The request could not be answered`). Refuse on purpose with `app-server-refuse` and a status.
21. **shared/ runs on both sides**: no react.el and no app-server.el at load time.
22. **The closing markers in index.html begin their own lines.**
23. **Hash mode is the default and needs nothing**: a static host, elisp-studio's preview. Path mode needs a server that sends index.html for every page address (`app-server-page-function` under serve-project.sh), a `nextel-base-path` that matches where it is, and script `src`s that resolve from deep paths.
24. **The router calls `nextel-navigate-functions`** at the first render and on every change of path or query (also query only), once per address, before a `:load` page's data comes.
25. **Only top-level `pages/_layout.el` and `pages/404.el` are special**; one layout, no nesting.
26. **HTTP methods are exact strings**: `"GET"`, not `"get"` or `'get`; HEAD and OPTIONS are not answered unless a file handles them.
27. **What more than one route needs belongs in shared/ or a helper of api/** (`api/_name.el`), as do `app-server-defjob` calls: under elisp-studio's CGI (`app-server-single-request`) a route file is loaded only when a request for its pattern comes, so a function defined in `api/a.el` is not there when `api/b.el` answers (a `void-function` error), and a job defined in a route file is unknown to `job.sh`.

<a id="worked-example"></a>
## Worked example

A list of items: `/` lists them and adds one (POST), `/item/ID` shows one (`:load` with GET), `/api/items` and `/api/items/ID` answer on the server. All files below were run as they are: routes written with `bin/nextel-routes`, tests passed (2/2), served with `serve-project.sh`, and used in Chrome (list, add, item page, error, 404).

```text
index.html  routes.el  server.el
pages/_layout.el  pages/index.el  pages/item/[id].el  pages/404.el
api/_store.el  api/items.el  api/items/[id].el
shared/types.el
test/demo-test.el
vendor/elisp-next/   (see "vendor/elisp-next" above)
```

`index.html` (before the routes are written):

```html
<!doctype html>
<html lang="en">
  <head>
    <meta charset="utf-8">
    <meta name="viewport" content="width=device-width, initial-scale=1">
    <title>Demo</title>
  </head>
  <body>
    <div id="app">Loading Emacs…</div>
    <!-- nextel:framework -->
    <!-- /nextel:framework -->
    <!-- nextel:pages -->
    <!-- /nextel:pages -->
    <script type="module" src="https://modeverv.github.io/elisp-react/js/elisp-react.js"></script>
  </body>
</html>
```

`shared/types.el`:

```elisp
;;; types.el --- what the page and the server send each other  -*- lexical-binding: t; -*-

(require 'nextel-schema)

(nextel-defschema demo-item
  "An item of the list."
  (id string :required t)
  (title string :required t)
  (done boolean))

(nextel-defschema demo-new-item
  "The body of POST /api/items."
  (title string :required t))

;;; types.el ends here
```

`api/_store.el`:

```elisp
;;; _store.el --- the items, kept by the server  -*- lexical-binding: t; -*-

;; A helper of api/ (its name starts with _): loaded before the routes,
;; never a route itself.

(require 'seq)

(defun demo-items ()
  "The items, oldest first."
  (app-server-read "items" nil))

(defun demo-find-item (id)
  "The item whose id is ID, or nil."
  (seq-find (lambda (item) (equal (demo-item-id item) id)) (demo-items)))

;;; _store.el ends here
```

`api/items.el`:

```elisp
;;; items.el --- GET and POST /api/items  -*- lexical-binding: t; -*-

(nextel-handle "GET"
  :returns '(list-of demo-item)
  :handler (lambda (_request) (demo-items)))

;; The body is checked against demo-new-item before the handler runs.
(nextel-handle "POST"
  :accepts 'demo-new-item
  :returns 'demo-item
  :handler (lambda (request)
             (let* ((items (demo-items))
                    (item (make-demo-item :id (number-to-string (1+ (length items)))
                                          :title (demo-new-item-title (plist-get request :body)))))
               (app-server-write "items" (append items (list item)))
               item)))

;;; items.el ends here
```

`api/items/[id].el`:

```elisp
;;; [id].el --- GET /api/items/ID  -*- lexical-binding: t; -*-

(nextel-handle "GET"
  :returns 'demo-item
  :handler (lambda (request)
             (or (demo-find-item (plist-get (plist-get request :params) :id))
                 (app-server-refuse "No such item" 404))))

;;; [id].el ends here
```

`server.el`:

```elisp
;;; server.el --- the server side: the files of api/  -*- lexical-binding: t; -*-

(declare-function nextel-server-load "nextel-server")
(load (expand-file-name "vendor/elisp-next/lisp/nextel-server.el" app-server-project-directory) nil t)
(nextel-server-load)

;;; server.el ends here
```

`pages/_layout.el`:

```elisp
;;; _layout.el --- around every page  -*- lexical-binding: t; -*-

;; The document's title for every page: "TITLE - Demo", or "Demo".
(setq nextel-title-function (lambda (title) (if title (concat title " - Demo") "Demo")))

(nextel-layout Layout
  :render (lambda (self)
            (jsx (div (:class "layout")
                   (header (Link (:href (nextel-href "/") :class "home") "Demo"))
                   (main (react-props self :children))))))

;;; _layout.el ends here
```

`pages/index.el`:

```elisp
;;; index.el --- /: the items, and a field to add one  -*- lexical-binding: t; -*-

(defun demo-add-item (self)
  "Send the draft of the page SELF to the server, then load the data again."
  (let ((title (string-trim (react-state self :draft))))
    (react-set-state self :draft "" :problem nil)
    (react-async
      (condition-case failure
          (progn
            (react-await (nextel-request "POST" "/api/items"
                                         :body (list :title (and (not (string-empty-p title)) title))
                                         :sends 'demo-new-item
                                         :returns 'demo-item))
            (nextel-reload))
        ;; :sends failed: signalled at once, nothing was sent.
        (nextel-type-error (react-set-state self :problem (cadr failure)))
        ;; The server refused, or its answer was not a demo-item.
        (react-async-error (react-set-state self :problem (plist-get (cadr failure) :message)))))))

(nextel-page HomePage
  :load (lambda (_route) (nextel-request "GET" "/api/items" :returns '(list-of demo-item)))
  :head (lambda (_route items) (list :title (format "%d items" (length items))))
  :initial-state (lambda (_props) (list :draft "" :problem nil))
  :render
  (lambda (self)
    (jsx (div (:class "home")
           (ul (:class "items")
             (mapcar (lambda (item)
                       (jsx (li (:key (demo-item-id item))
                              (Link (:href (nextel-href "/item/[id]" :id (demo-item-id item)))
                                (demo-item-title item)))))
                     (nextel-data self)))
           (input (:class "draft" :value (react-state self :draft)
                   :on-input (lambda (event) (react-set-state self :draft (plist-get event :value)))))
           (button (:class "add" :type "button" :on-click (lambda (_event) (demo-add-item self))) "Add")
           (and (react-state self :problem) (jsx (p (:class "problem") (react-state self :problem))))))))

;;; index.el ends here
```

`pages/item/[id].el`:

```elisp
;;; [id].el --- /item/ID: one item  -*- lexical-binding: t; -*-

(nextel-page ItemPage
  :load (lambda (route)
          (nextel-request "GET" "/api/items/[id]" :id (nextel-param route :id) :returns 'demo-item))
  :head (lambda (_route item)
          (list :title (demo-item-title item) :description (format "Item %s" (demo-item-id item))))
  :loading (lambda (route) (jsx (p (:class "loading") "Loading item " (nextel-param route :id))))
  :error (lambda (_route error retry)
           (jsx (div (:class "failed")
                  (p (plist-get error :message))
                  (button (:type "button" :on-click (lambda (_event) (funcall retry))) "Retry"))))
  :render (lambda (self)
            (let ((item (nextel-data self)))
              (jsx (article (:class "item")
                     (h1 (demo-item-title item))
                     (p (if (demo-item-done item) "done" "to do"))
                     (Link (:href (nextel-href "/")) "All items"))))))

;;; [id].el ends here
```

`pages/404.el`:

```elisp
;;; 404.el --- an address that no file of pages/ has  -*- lexical-binding: t; -*-

(nextel-page NotFoundPage
  :head (lambda (_route _data) (list :title "Not found"))
  :render (lambda (self)
            (jsx (p (:class "missing") "Nothing at " (plist-get (react-props self :route) :path)))))

;;; 404.el ends here
```

Write the routes (in the project):

```text
$ vendor/elisp-next/bin/nextel-routes --check
nextel: not up to date: routes.el, index.html; write them (M-x nextel-write-routes, bin/nextel-routes)
$ vendor/elisp-next/bin/nextel-routes
nextel: 2 pages, 2 API routes: wrote routes.el, index.html
$ vendor/elisp-next/bin/nextel-routes --check
nextel: the routes are up to date
```

<a id="example-routes"></a>
`routes.el`, as written:

```elisp
;;; routes.el --- which page is which address  -*- lexical-binding: t; -*-

;; Written by nextel-build.el (elisp-next) from pages/: do not edit,
;; write it again (M-x nextel-write-routes, or bin/nextel-routes).
;;
;; The server's routes, from api/ (nextel-server.el reads that directory itself):
;;   /api/items/[id]  api/items/[id].el
;;   /api/items    api/items.el

(nextel-define-routes
 '(("/item/[id]" . ItemPage)
   ("/" . HomePage))
 :layout 'Layout
 :not-found 'NotFoundPage)

(nextel-start "#app")

;;; routes.el ends here
```

index.html's regions, as written:

```html
    <!-- nextel:framework -->
    <script type="text/emacs-lisp" src="vendor/elisp-next/lisp/nextel-schema.el"></script>
    <script type="text/emacs-lisp" src="vendor/elisp-next/lisp/nextel-route.el"></script>
    <script type="text/emacs-lisp" src="vendor/elisp-next/lisp/nextel.el"></script>
    <script type="text/emacs-lisp" src="shared/types.el"></script>
    <!-- /nextel:framework -->
    <!-- nextel:pages -->
    <script type="text/emacs-lisp" src="pages/_layout.el"></script>
    <script type="text/emacs-lisp" src="pages/404.el"></script>
    <script type="text/emacs-lisp" src="pages/index.el"></script>
    <script type="text/emacs-lisp" src="pages/item/[id].el"></script>
    <script type="text/emacs-lisp" src="routes.el"></script>
    <!-- /nextel:pages -->
```

<a id="example-test"></a>
`test/demo-test.el`, run with checkouts of elisp-react and elisp-studio next to the project:

```sh
ELISP_STUDIO=../elisp-studio emacs --batch -Q -L ../elisp-react/lisp -l test/demo-test.el -f ert-run-tests-batch-and-exit
```

```elisp
;;; demo-test.el --- the example application, pages and server in one native Emacs  -*- lexical-binding: t; -*-

;; emacs --batch -Q -L ../elisp-react/lisp -l test/demo-test.el -f ert-run-tests-batch-and-exit
;; (ELISP_STUDIO: a checkout of elisp-studio, for app-server.el.)

(require 'ert)
(require 'cl-lib)
(require 'react-testing)

(defconst demo-root
  (file-name-directory (directory-file-name (file-name-directory (or load-file-name buffer-file-name)))))

;;;; The server: app-server.el, then server.el, as serve-project.el does.

(load (expand-file-name "lisp/app-server.el" (getenv "ELISP_STUDIO")) nil t)
(setq app-server-data-directory (file-name-as-directory (make-temp-file "demo-data" t)))
(app-server-use-project demo-root)
(load (expand-file-name "server.el" demo-root) nil t)

(defun demo-call (method path &optional body)
  "(STATUS TEXT) of the server's answer to METHOD PATH with BODY."
  (let ((answer (app-server-respond method path (or body "") nil)))
    (list (aref answer 0) (aref answer 1))))

;;;; The page: the scripts of index.html, in their order, as elisp-react.js loads them.

(defun demo-scripts ()
  (with-temp-buffer
    (insert-file-contents (expand-file-name "index.html" demo-root))
    (let (scripts)
      (while (re-search-forward "<script type=\"text/emacs-lisp\" src=\"\\([^\"]+\\)\"" nil t)
        (push (match-string 1) scripts))
      (nreverse scripts))))

(defun demo-start (href)
  "Load the page at HREF (\"#/item/1\")."
  (react-testing-reset)
  (react-testing-location href)
  (dolist (script (demo-scripts))
    (load (expand-file-name script demo-root) nil t))
  (react-testing-flush))

(defun demo-go (href)
  (react-testing-location href))

(defun demo-serve ()
  "Answer every fetch the page waits for with what the server answers."
  (let (request)
    (while (setq request (cl-find "fetch" react-testing-requests :key #'cadr :test #'equal))
      (let* ((argument (nth 2 request))
             (answer (demo-call (plist-get argument :method) (concat "/" (plist-get argument :url))
                                (plist-get argument :body))))
        (react-testing-answer-fetch (car answer) (cadr answer))))))

(defun demo-told (command)
  (mapcar #'cadr (cl-remove-if-not (lambda (told) (equal (car told) command)) react-testing-told)))

;;;; Tests

(ert-deftest demo-server ()
  (app-server-write "items" nil)
  (should (equal (demo-call "GET" "/api/items") '(200 "nil")))
  (should (equal (demo-call "POST" "/api/items" "(:title \"Milk\")") '(200 "(:id \"1\" :title \"Milk\")")))
  (should (equal (demo-call "GET" "/api/items") '(200 "((:id \"1\" :title \"Milk\"))")))
  (should (equal (demo-call "GET" "/api/items/1") '(200 "(:id \"1\" :title \"Milk\")")))
  (should (equal (demo-call "GET" "/api/items/9") '(404 "\"No such item\"")))
  (should (equal (demo-call "POST" "/api/items" "(:title 3)") '(400 "\"body.title: expected string, got 3\"")))
  (should (equal (demo-call "POST" "/api/items" "") '(400 "\"body.title is required\"")))
  (should (equal (demo-call "POST" "/api/items" "(:title \"x\" :done t)")
                 '(400 "\"body: no field :done in demo-new-item\"")))
  (should (equal (demo-call "DELETE" "/api/items") '(405 "\"DELETE is not allowed at /api/items\"")))
  (should (equal (demo-call "GET" "/api/nothing") '(404 "\"No such API: /api/nothing\""))))

(ert-deftest demo-pages ()
  (app-server-write "items" nil)
  (demo-start "#/")
  ;; :load asked the server; nothing is shown meanwhile (the default :loading).
  (should (equal (react-testing-html) "<div class=\"layout\"><header><a href=\"#/\" class=\"home\">Demo</a></header><main></main></div>"))
  (demo-serve)
  (should (equal (car (last (demo-told "title"))) '(:text "0 items - Demo")))
  ;; Add an item: POST, then `nextel-reload' loads the list again.
  (react-testing-input (react-testing-find :class "draft") "Milk")
  (react-testing-click (react-testing-find :class "add"))
  (demo-serve)
  (should (equal (react-testing-text (react-testing-find :tag 'li)) "Milk"))
  (should (equal (react-testing-attribute (react-testing-find :tag 'a :text "Milk") "href") "#/item/1"))
  ;; An empty title: :sends refuses it in the page, nothing is sent.
  (react-testing-click (react-testing-find :class "add"))
  (should-not react-testing-requests)
  (should (equal (react-testing-text (react-testing-find :class "problem"))
                 "POST /api/items body.title is required"))
  ;; The item's page: :loading, then the page with its data and head.
  (demo-go "#/item/1")
  (should (equal (react-testing-text (react-testing-find :class "loading")) "Loading item 1"))
  (demo-serve)
  (should (equal (react-testing-text (react-testing-find :tag 'h1)) "Milk"))
  (should (equal (car (last (demo-told "title"))) '(:text "Milk - Demo")))
  (should (equal (car (last (demo-told "meta"))) '(:name "description" :content "Item 1")))
  ;; A refusal of the server reaches :error as (:status 404 :message ...).
  (demo-go "#/item/9")
  (demo-serve)
  (should (equal (react-testing-text (react-testing-find :class "failed")) "No such itemRetry"))
  ;; No file for the address: pages/404.el, in the layout.
  (demo-go "#/nowhere")
  (should (equal (react-testing-text (react-testing-find :class "missing")) "Nothing at /nowhere"))
  (should (equal (car (last (demo-told "title"))) '(:text "Not found - Demo"))))

;;; demo-test.el ends here
```

```text
   passed  1/2  demo-pages
   passed  2/2  demo-server
Ran 2 tests, 2 results as expected, 0 unexpected
```

Serve it and ask the API (a native Emacs; Ctrl-C stops it):

```text
$ ../elisp-studio/tools/serve-project.sh . 8731
serve-project: server.el loaded api/items/[id].el, api/items.el, api/_store.el, shared/types.el, vendor/elisp-next/lisp/nextel-server.el, ...
serve-project: http://127.0.0.1:8731/ (...)

$ curl http://127.0.0.1:8731/api/items
nil
$ curl -X POST -H 'Origin: http://127.0.0.1:8731' --data '(:title "Milk")' http://127.0.0.1:8731/api/items
(:id "1" :title "Milk")
$ curl http://127.0.0.1:8731/api/items/1
(:id "1" :title "Milk")
$ curl -w ' %{http_code}\n' -X POST --data '(:title 3)' http://127.0.0.1:8731/api/items
"body.title: expected string, got 3" 400
$ curl -w ' %{http_code}\n' http://127.0.0.1:8731/api/items/9
"No such item" 404
$ curl -w ' %{http_code}\n' -X POST -H 'Origin: http://evil.example' --data '(:title "x")' http://127.0.0.1:8731/api/items
"requests from other sites are refused" 403
```

Open `http://127.0.0.1:8731/` in a browser for the page itself (it fetches elisp-react and Emacs from their sites the first time): the list, Add, `#/item/1` with the title `Milk - Demo` and the description `Item 1`, `#/item/9` with `No such item` and Retry, `#/nowhere` with the 404 page. The items are in `.data/items.eld`.
