---
name: elisp-react
description: Write web pages and applications in Emacs Lisp with elisp-react, React written in Emacs Lisp: GNU Emacs runs in the web page as WebAssembly, components with props and state render through a keyed reconciler, and a jsx macro writes the markup. Use when creating or changing an elisp-react page, component or test, when an HTML file has script tags of type text/emacs-lisp, or when code uses react-define-component, jsx, react-set-state, react-effect, react-query, react-async, react-fetch or react-testing.
---

# elisp-react

**Before you write or change any code, read [doc/api.md](doc/api.md).** It is the complete API of elisp-react, written from the code; every Lisp block in it was run, with the values it shows. Do not guess: a function, key, prop, event field or behaviour that doc/api.md does not describe does not exist. Where doc/api.md and README.md or a docstring differ, doc/api.md is right.

If doc/api.md is not next to this file, read <https://raw.githubusercontent.com/modeverv/elisp-react/main/doc/api.md>. It describes `main` (protocol 3). A page that pins an older release (`v/0.1.0/`) has protocol 2: no fragments and no `react-inspect`.

For an application with pages as files, API routes and shared types, use elisp-next on top of this (its own skill and API: <https://raw.githubusercontent.com/modeverv/elisp-next/main/doc/api.md>).

## What to read for what

| You are about to | Read in doc/api.md |
|---|---|
| find whether something exists | [Index](doc/api.md#index), every public symbol with a link |
| understand when things run | [Mental model](doc/api.md#mental-model), with the render cycle and the lifecycle order |
| write index.html | [Page setup](doc/api.md#page-setup) |
| write markup, props and event handlers | [Elements](doc/api.md#elements) |
| define a component | [Components](doc/api.md#components) |
| use state, effects, context, refs, timers, fetch, storage, the query cache, the address, page JavaScript | [Reference](doc/api.md#reference), the section of that area |
| wait for something (fetch, timers) in sequence | [Async](doc/api.md#async) |
| test without a browser | [Testing](doc/api.md#testing) |
| anything | [Rules and pitfalls](doc/api.md#rules-and-pitfalls), all 30, once |
| start from working code | [Worked examples](doc/api.md#worked-examples): counter, todo list, loading data, a context, a test |

## Workflow

1. Write index.html as [Page setup](doc/api.md#page-setup) shows. Put a `<div id="app">` in it, then the `<script type="text/emacs-lisp">` files in the order they depend on each other, then the host script.
2. Write components with `react-define-component` and `jsx`. The file that calls `react-mount` comes last.
3. Lint: byte-compile every file with warnings as errors.

   ```sh
   emacs --batch -Q -L path/to/elisp-react/lisp -l react --eval '(setq byte-compile-error-on-warn t)' -f batch-byte-compile app.el
   ```

4. Test with `react-testing.el`, in a file that the page does not list.

   ```sh
   emacs --batch -Q -L path/to/elisp-react/lisp -L . -l app-test.el -f ert-run-tests-batch-and-exit
   ```

5. Open the page from a web server (any static server). The first visit downloads Emacs, about 5 MB.

## Rules that are easy to break

These are a selection; [Rules and pitfalls](doc/api.md#rules-and-pitfalls) has all 30.

- Start every file with `-*- lexical-binding: t; -*-`.
- In `jsx`, component names are Capitalized. A list that starts with a tag name is markup, so you cannot call a function named like a tag there.
- All files share one Emacs. Prefix your functions and variables, and do not name a component like an HTML tag.
- Give every child of a list that changes a `:key`.
- Never change state in place. Build new values (`react-plist-with`, `mapcar`, `seq-remove`, `append`).
- `react-set-state` does not render at once. The render happens at the end of the call from the page, and several calls make one render.
- An event is `:on-` plus the DOM event type (`:on-input`, `:on-keydown`). Lisp cannot cancel a default action afterwards: use `(react-handler f :prevent t)`.
- `react-await` only works directly in the body of `react-async`. It does not work inside `lambda`, `mapcar` or `unwind-protect`; loop with `dolist` or `while`.
- `react-query`'s loader returns a function of `(RESOLVE REJECT)`, such as `react-fetch-async`, not a `react-async` task.
- What starts in `:did-mount` or an effect (intervals, listeners, watchers, connections) stops in `:will-unmount` or the effect's cleanup.
- Data sent to the page is JSON. Use plists with keyword keys, vectors and strings, not symbols or plain lists.
