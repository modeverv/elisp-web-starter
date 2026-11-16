# elisp-next API

> この文書は [doc/api.md](api.md) の日本語訳です（訳した時点の英語版：`868cac7`）。英語版と食い違うときは英語版が、英語版とソースが食い違うときはソースが正しいものとします。

elisp-next の完全な API です。コーディングエージェントが推測せずにアプリケーションを作れるように書いています。Next.js、React、Emacs Lisp の知識を前提とし、elisp-next と elisp-react については何も前提としません。

対象は v0.1.2、つまり `main` の `lisp/` です。v0.1.1 は、api/ のすべてのファイルを起動時に読み込み（CGI の下でも同じ）、ソースからしか読み込みませんでした。v0.1.0 はさらに3か所が異なり、それぞれ該当する箇所で述べます。`nextel-stale-ms` に効果がなかったこと、サーバーが api/ の隠しファイルを読み込んだこと、メソッドがより具体的でないファイルへ流れていたことです。以下に引用するメッセージ、値、HTML はすべて、GNU Emacs 31.1 のバッチでコードを実行して得たものです。ページ側には elisp-react の `react-testing.el`、サーバー側には elisp-studio の `app-server.el` を使いました。[作例](#worked-example)も同じように実行し、`serve-project.sh` で配信して Chrome で使いました。

elisp-next は2つのライブラリの上にあります。[elisp-react](https://github.com/modeverv/elisp-react)（Emacs Lisp で書いた React。GNU Emacs が WebAssembly として Web ページの中で動きます）と、[elisp-studio](https://github.com/modeverv/elisp-studio) の `app-server.el`（サーバー）です。アプリケーションに必要な部分は [elisp-react と app-server.el から](#from-elisp-react)にあります。残りはそれぞれの README にあります。

1. [索引](#index)
2. [全体像](#mental-model)
3. [プロジェクトの構成](#project-layout)
4. [ページ](#pages)
5. [アドレスとナビゲーション](#addresses-and-navigation)
6. [パターン](#patterns)
7. [リクエスト](#requests)
8. [スキーマ](#schemas)
9. [サーバー](#server)
10. [ルート表の書き出し](#routes-writer)
11. [elisp-react と app-server.el から](#from-elisp-react)
12. [アプリケーションのテスト](#testing)
13. [規則と落とし穴](#pitfalls)
14. [作例](#worked-example)

<a id="index"></a>
## 索引

elisp-next の5つのファイルが定義するシンボルのうち、名前に `--` を含まないものすべてです。名前は53個、項目は54個です（`nextel-layout` はマクロでもあり変数でもあります）。存在する場所は、**P** がページ（index.html が読み込みます）、**S** がサーバー（server.el が読み込みます）、**E** がルート表を書き出す Emacs（あなたのもの、elisp-studio のもの、またはバッチのもの）です。

| シンボル | 種類 | 場所 | 用途 |
|---|---|---|---|
| [`Link`](#link) | コンポーネント | P | リンク。`<a>` です。`path` モードでは Lisp がそれをたどります。 |
| [`nextel`](#nextel-group) | カスタムグループ | E | `nextel-routes-mode` のグループ。 |
| [`nextel-base-path`](#nextel-base-path) | 変数 | P | `path` モードでの、アプリケーションのパスの接頭辞。 |
| [`nextel-check`](#nextel-check) | 関数 | P S | VALUE が TYPE なら VALUE、そうでなければ `nextel-type-error` をシグナルします。 |
| [`nextel-check-routes`](#nextel-check-routes) | 関数 | E | バッチ用。routes.el か index.html が最新でなければ 1 で終了します。 |
| [`nextel-data`](#nextel-data) | 関数 | P | ページの `:load` が答えたもの。 |
| [`nextel-define-routes`](#nextel-define-routes) | 関数 | P | ルート表、レイアウト、404 ページを設定します（routes.el が呼びます）。 |
| [`nextel-defschema`](#nextel-defschema) | マクロ | P S | レコード型を定義します。コンストラクタ、述語、アクセサ。 |
| [`nextel-error-function`](#nextel-error-function) | 変数 | P | ページに `:error` がないときの、失敗した `:load` の要素。 |
| [`nextel-fill`](#nextel-fill) | 関数 | P S E | パターンとパラメータ → クエリ文字列付きのパス。 |
| [`nextel-go`](#nextel-go) | 関数 | P | パラメータを与えたパターンへ移動します。 |
| [`nextel-handle`](#nextel-handle) | 関数 | S | api/ のファイルの中で、あるメソッドが何をするか。 |
| [`nextel-href`](#nextel-href) | 関数 | P | リンク用の、ページのアドレス。 |
| [`nextel-index-text`](#nextel-index-text) | 関数 | E | 2つの領域を埋めた index.html のテキスト。 |
| [`nextel-layout`](#nextel-layout) | マクロ | P | レイアウトのコンポーネントを定義します。 |
| [`nextel-layout`](#nextel-layout-variable) | 変数 | P | 使用中のレイアウトのコンポーネント。 |
| [`nextel-loading-function`](#nextel-loading-function) | 変数 | P | `:loading` のないページの読み込み中に表示する要素。 |
| [`nextel-match`](#nextel-match) | 関数 | P S E | パスがパターンに一致するか。そのパラメータ。 |
| [`nextel-mount-selector`](#nextel-mount-selector) | 変数 | E | routes.el がアプリケーションをマウントするセレクタ。 |
| [`nextel-navigate`](#nextel-navigate) | 関数 | P | href へ移動します（新しい履歴項目、または置き換え）。 |
| [`nextel-navigate-functions`](#nextel-navigate-functions) | 変数 | P | ROUTE を引数とする関数群。新しいアドレスを描画したあとに実行されます。 |
| [`nextel-not-found`](#nextel-not-found) | 変数 | P | どのページにもないアドレスのページ。 |
| [`nextel-page`](#nextel-page) | マクロ | P | ページを定義します。`:load`、`:head`、`:loading`、`:error` を持つコンポーネント。 |
| [`nextel-page-props-function`](#nextel-page-props-function) | 変数 | P | `:route` と `:data` のほかに、すべてのページが受け取る props。 |
| [`nextel-param`](#nextel-param) | 関数 | P | ルートの `[name]` パラメータ。 |
| [`nextel-pattern-of-file`](#nextel-pattern-of-file) | 関数 | P S E | ファイルのパス → そのパターン。 |
| [`nextel-pattern-rank`](#nextel-pattern-rank) | 関数 | P S E | パターンの並べ替えのキー。 |
| [`nextel-pattern<`](#nextel-pattern-lessp) | 関数 | P S E | パターンを試す順序。 |
| [`nextel-project-root`](#nextel-project-root) | 関数 | E | ファイルの上位にある、index.html と pages/ を持つディレクトリ。 |
| [`nextel-query`](#nextel-query) | 関数 | P | ルートのクエリ文字列の値。 |
| [`nextel-read-project`](#nextel-read-project) | 関数 | E | pages/、api/、shared/ の中身。 |
| [`nextel-refresh`](#nextel-refresh) | 関数 | P | ルーターを、したがってページを、もう一度描画します。 |
| [`nextel-reload`](#nextel-reload) | 関数 | P | ページのデータをもう一度読み込みます。 |
| [`nextel-request`](#nextel-request) | 関数 | P | api/ のルートへの awaitable なリクエスト。型で検査されます。 |
| [`nextel-resolve`](#nextel-resolve) | 関数 | P | パスとクエリ文字列 → ルート。 |
| [`nextel-route`](#nextel-route) | 関数 | P | いま表示しているルート。 |
| [`nextel-router`](#nextel-router) | コンポーネント | P | ルーター。`nextel-start` がマウントします。 |
| [`nextel-routes`](#nextel-routes) | 変数 | P | 使用中のルート表。 |
| [`nextel-routes-file`](#nextel-routes-file) | 変数 | E | ルート表のファイル名 `"routes.el"`。 |
| [`nextel-routes-mode`](#nextel-routes-mode) | グローバルマイナーモード | E | pages/、api/、shared/ のファイルを保存するたびにルート表を書き出します。 |
| [`nextel-routes-mode-hook`](#nextel-routes-mode) | フック | E | モードをオンまたはオフにしたときに実行されます（`define-minor-mode` によるもの）。 |
| [`nextel-routes-text`](#nextel-routes-text) | 関数 | E | routes.el のテキスト。 |
| [`nextel-schema-fields`](#nextel-schema-fields) | 関数 | P S | スキーマのフィールド。 |
| [`nextel-server-handle`](#nextel-server-handle) | 関数 | S | METHOD PATH BODY に api/ から答えます。`app-server-handle` になります。 |
| [`nextel-server-load`](#nextel-server-load) | 関数 | S | shared/ と api/ を読み込み、それらで /api/ に答えます。 |
| [`nextel-server-routes`](#nextel-server-routes) | 変数 | S | API のルート表。これまでに読み込んだルート。 |
| [`nextel-server-lazy`](#nextel-server-lazy) | 変数 | S | api/ のファイルを、リクエストが初めてそれを必要としたときに読み込みます。 |
| [`nextel-stale-ms`](#nextel-stale-ms) | 変数 | P | ページのデータが新しいとみなされる時間。それより古いデータは、ルーターがそのアドレスに戻ってきたときにもう一度読み込まれます。 |
| [`nextel-start`](#nextel-start) | 関数 | P | ルーターをマウントします（routes.el が呼びます）。 |
| [`nextel-title-function`](#nextel-title-function) | 変数 | P | `:head` のタイトル → 文書のタイトル。 |
| [`nextel-type-error`](#nextel-type-error) | エラーシンボル | P S | 型の検査がシグナルするもの。 |
| [`nextel-type-p`](#nextel-type-p) | 関数 | P S | VALUE が TYPE なら non-nil。 |
| [`nextel-url-mode`](#nextel-url-mode) | 変数 | P | アドレスのどこにルートがあるか。`hash`（デフォルト）か `path`。 |
| [`nextel-watch-routes`](#nextel-watch-routes) | 関数 | E | バッチ用。ファイルが変わるたびにルート表を書き出します。 |
| [`nextel-write-routes`](#nextel-write-routes) | コマンド | E | routes.el と index.html の `<script>` タグを書き出します。 |

`(nextel-defschema NAME ...)` はそれぞれ、`make-NAME`、`NAME-p`、そしてフィールドごとに `NAME-FIELD` も定義します（[詳細](#nextel-defschema)）。feature は `nextel`、`nextel-schema`、`nextel-route`、`nextel-server`、`nextel-build` です。設定はただの `defvar` なので、`setq` で設定します。

<a id="mental-model"></a>
## 全体像

アプリケーションは2つの Emacs の上で動きます。2つが共有するのはファイルで、メモリではありません。3つ目の Emacs がルート表を書き出します。

| | ページ | サーバー |
|---|---|---|
| 実体 | ブラウザのタブの中で WebAssembly として動く GNU Emacs 30.2（elisp-react） | ネイティブの Emacs（`tools/serve-project.sh`、ダウンロードしたプロジェクトの `run.sh`）、または elisp-studio のブラウザのタブの中の3つ目の Emacs |
| 読み込むもの | react.el（elisp-react.js が最初に読み込みます）、次に index.html の `<script type="text/emacs-lisp">` を文書の順に | app-server.el、次にプロジェクトの server.el |
| elisp-next | nextel-schema.el、nextel-route.el、nextel.el | nextel-server.el（これが nextel-schema.el と nextel-route.el を読み込みます） |
| プロジェクトのファイル | shared/、あなた自身の Lisp、pages/、routes.el | shared/、api/ |

ルート表の書き出し（nextel-build.el。`M-x nextel-write-routes`、`nextel-routes-mode`、または `bin/nextel-routes`）は、pages/、api/、shared/ を読み、routes.el と script タグを書き出します。ページはディレクトリを一覧できないからです。

**ページは次の順に読み込みます**（2つの領域はルート表の書き出しが書きます）。

1. react.el。elisp-react.js が読み込みます。
2. 領域 `nextel:framework`：`vendor/elisp-next/lisp/nextel-schema.el`、`nextel-route.el`、`nextel.el`、次に shared/ のすべてのファイルをパス順に。
3. あなた自身のスクリプト。2つの領域の間に置きます。
4. 領域 `nextel:pages`：`pages/_layout.el`、pages/ のほかの補助ファイル（名前が `_` で始まるもの）を並べた順に、ページのファイルを並べた順に（404.el もここに含まれます）、最後に `routes.el`。
5. routes.el が `(nextel-define-routes ...)` と `(nextel-start "#app")` を呼びます。ルーターがマウントされ、現在のアドレスのページを描画します。

**リクエストの一部始終：**

1. ルーターがアドレスを読み（`react-location`）、それを[ルート](#route-plist)に解決します。
2. ページの `:load` がルートを引数に実行され、`(nextel-request "GET" "/api/items/[id]" :id ID :returns 'demo-item)` を返します。
3. ページが `api/items/ID` を fetch します（hash モードでは文書からの相対）。本文（body）があれば、それは print した Lisp です。
4. サーバーの `app-server-respond` が `app-server-handle` を呼びます。これは `nextel-server-load` によって `nextel-server-handle` になっています。パターンが一致する api/ のファイルと、その中のメソッドを見つけます。
5. 本文（body）はデータとして読まれ（`app-server-data`。評価はされません）、`:accepts` で検査されます（不正なら 400）。ハンドラがリクエストの plist を引数に実行されます。その答えが `:returns` で検査され（不正なら 500）、print されます。
6. ページは答えを読み、`:returns` で検査し（不正なら失敗）、それを `:data` としてページを描画します。

**URL モード**（`nextel-url-mode`）：

| | `hash`（デフォルト） | `path` |
|---|---|---|
| ルートがある場所 | ハッシュ：`#/item/1?x=2` | パスとクエリ文字列。`nextel-base-path` の下 |
| 無視されるもの | 文書のパスとクエリ文字列 | ハッシュ |
| `(nextel-href "/item/[id]" :id "1")` | `"#/item/1"` | `"/app/item/1"`（ベースパスが `"/app"` のとき） |
| `Link` | ブラウザがたどる `<a>`。ルーターはハッシュの変化を受け取ります | クリックを Lisp が処理する `<a>`（`nextel-navigate`）。ブラウザはページを読み込みません |
| `nextel-request` の URL | 相対：`api/items/1` | `BASE/api/items/1` |
| ホスティング | 任意の静的ホスト、elisp-studio のプレビュー | サーバーは、ページのすべてのアドレスに対して index.html を送る必要があります |

<a id="project-layout"></a>
## プロジェクトの構成

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
### ファイル名

パターンは、ファイルのパスから `.el` を除いたものです。api/ では、パスに `api/` を含みます。`nextel-pattern-of-file` で確認しました。

| ファイル | パターン | パラメータ |
|---|---|---|
| `pages/index.el` | `/` | |
| `pages/blog/index.el` | `/blog` | |
| `pages/watch.el` | `/watch` | |
| `pages/channel/[id].el` | `/channel/[id]` | `:id`、1セグメント |
| `pages/docs/[...path].el` | `/docs/[...path]` | `:path`、1つ以上のセグメントのリスト。最後のセグメントとしてのみ使えます |
| `pages/About.el` | `/About` | 大文字小文字はそのまま。照合は大文字小文字を区別します |
| `api/feed/index.el` | `/api/feed` | |
| `api/later/[id].el` | `/api/later/[id]` | `:id` |

pages/：

- `_layout.el`（最上位のみ）はレイアウトです。`(nextel-layout NAME` を含む必要があります。
- `404.el`（最上位のみ）は `:not-found` で、ルートを持ちません。`(nextel-page NAME` を含む必要があります。`pages/blog/404.el` は普通のルート `/blog/404` です。
- 名前が `_` で始まるファイルやディレクトリは補助ファイルです。ページはそれを（`_layout.el` のあとに）読み込みますが、ルートではありません。
- 名前が `.` で始まるファイルやディレクトリは無視されます（Emacs のロックファイル `.#x.el`）。対象になるのは `*.el` だけです（`.elc` や `~` のバックアップは対象外）。
- それ以外のファイルはすべて、`(nextel-page NAME` というテキストを含む必要があります。含まないと書き出しが失敗します：`pages/broken.el has no (nextel-page NAME ...)`。
- 同じパターンのファイルが2つあると失敗します：`pages/news.el and pages/news/index.el are both /news`。
- `[[...name]]`（省略可能なキャッチオール）とルートグループ `(name)` はサポートしていません。

api/：

- 名前が `_` で始まるファイルやディレクトリは補助ファイルで、ルートより前にパス順で読み込まれます。それ以外の `*.el` はすべてルートで、いくつのメソッドを扱っても構いません。
- サーバーは隠しファイルと隠しディレクトリも飛ばします（v0.1.1 から。v0.1.0 はそれらを読み込み、Emacs のロックファイルがあると起動できませんでした）。
- 同じパターンのファイルが2つあっても（`api/things.el`、`api/things/index.el`）エラーではありません。両方が登録され、メソッドごとに最初に読み込まれたもの（パス順）が勝ちます。

shared/：その下のすべての `*.el` を、パス順に読み込みます（`shared/sub/a.el` は `shared/z.el` より前）。両側が読み込みます。ページはあなたのスクリプトとページより前に、サーバーは api/ より前に読み込みます。shared/ のファイルが使えるのは nextel-schema.el と Emacs だけです。react.el（サーバーにはありません）も app-server.el（ページにはありません）も使えません。ファイルの先頭の `(require 'nextel-schema)` は両側で動きます。

<a id="index-html"></a>
### index.html

必要なのは、マウントする要素（`<div id="app">`。[`nextel-mount-selector`](#nextel-mount-selector) のセレクタ）、2つの領域、そしてそのあとに置く elisp-react のスクリプトです。

```html
    <div id="app">Loading Emacs…</div>
    <!-- nextel:framework -->
    <!-- /nextel:framework -->
    <!-- nextel:pages -->
    <!-- /nextel:pages -->
    <script type="module" src="https://modeverv.github.io/elisp-react/js/elisp-react.js"></script>
```

- 開始マーカーはどこにあっても構いません。終了マーカーは行の先頭になければなりません（前に置けるのは空白とタブだけです）。両方が1行にあると失敗します：`index.html has no <!-- /nextel:framework -->`。開始マーカーがないとき：`index.html has no <!-- nextel:framework --> ... <!-- /nextel:framework -->`。
- 対になったマーカーの間は、改行、ファイルごとに1つの `    <script type="text/emacs-lisp" src="PATH"></script>`（空白4つ）、そして改行で置き換えられます。終了マーカーの行はそのまま残ります。
- あなた自身の `<script type="text/emacs-lisp">` タグは、`<!-- /nextel:framework -->` と `<!-- nextel:pages -->` の間に置きます。elisp-next と shared/ のあと、ページより前に読み込まれます。
- 角括弧を含むページの `src` は、そのまま書かれます（`pages/item/[id].el`）。serve-project.sh は、それを生のままでも `%5Bid%5D` としても配信します。

<a id="server-el"></a>
### server.el

```elisp
(declare-function nextel-server-load "nextel-server")
(load (expand-file-name "vendor/elisp-next/lisp/nextel-server.el" app-server-project-directory) nil t)
(nextel-server-load)
```

- serve-project.el は、server.el を読み込む前にバイトコンパイルします。1行目がないと、起動のたびにコンパイラが `the function ‘nextel-server-load’ is not known to be defined` と警告します。
- `app-server-project-directory` は、プロジェクト（ネイティブ）、またはタブが持つそのテキストファイルのコピー（elisp-studio）です。
- `nextel-server-load` は `app-server-handle` を `nextel-server-handle` の別名にします。server.el は独自の `app-server-handle` を定義してはいけません。

<a id="vendor"></a>
### vendor/elisp-next

ページは elisp-next をプロジェクトから読み込みます（elisp-studio のプレビューは、ほかのサイトから何も読み込みません）。プロジェクトの中で次を実行します。

```sh
mkdir -p vendor/elisp-next
curl -L https://github.com/modeverv/elisp-next/archive/refs/tags/v0.1.2.tar.gz \
  | tar -xz --strip-components=1 -C vendor/elisp-next elisp-next-0.1.2/lisp elisp-next-0.1.2/bin elisp-next-0.1.2/LICENSE
```

ルート表の書き出しは、自分自身のディレクトリを、プロジェクトからの相対パスで framework 領域に書きます。そのため、プロジェクトの中にあるコピーでなければなりません（中であればどのディレクトリでも動きます。`lib/next/lisp/` で試しました）。外にあるコピーは失敗します：`nextel: load the copy of nextel-build.el that is in the project (vendor/elisp-next/lisp/), not DIRECTORY`。

<a id="pages"></a>
## ページ

<a id="nextel-page"></a>
### `(nextel-page NAME &rest SPEC)` — マクロ

ページのコンポーネント NAME（クォートしないシンボル）を定義します。SPEC は `react-define-component` の plist に、4つのキーを加えたものです。展開すると次のようになります。

```elisp
(nextel-page P :load L :head H :render R :initial-state I)
;; =>
(progn (put 'P 'nextel-page (list :load L :head H))
       (react-define-component 'P :render R :initial-state I))
```

| キー | 呼び出しの引数 → 戻り値 | |
|---|---|---|
| `:load` | `(ROUTE)` → awaitable | ページのデータ。[後述](#load)。 |
| `:loading` | `(ROUTE)` → 要素 | `:load` の実行中に表示されます。デフォルトは [`nextel-loading-function`](#nextel-loading-function)。 |
| `:error` | `(ROUTE ERROR RETRY)` → 要素 | `:load` が失敗したあとに表示されます。デフォルトは [`nextel-error-function`](#nextel-error-function)。 |
| `:head` | `(ROUTE DATA)` → `(:title TEXT :description TEXT :meta ((NAME . CONTENT) ...))` | 文書のタイトルと `<meta>`。[後述](#head)。 |
| `:render` | `(SELF)` → 要素 | 必須。 |
| `:initial-state`, `:did-mount`, `:did-update`, `:will-unmount`, `:should-update`, `:pure`, `:did-catch` | [`react-define-component`](#from-elisp-react) と同じ | |

もう一度評価すると（elisp-studio は保存したファイルを再読み込みします）、コンポーネントとその4つのキーの両方が置き換わります。マウント済みのインスタンスは、それぞれの state のままもう一度描画されます。

ページの props（確認済み）：

```elisp
(:key ItemPage
 :route (:page ItemPage :pattern "/item/[id]" :path "/item/a" :params (:id "a") :query nil)
 :data (:title "A")
 ;; then what nextel-page-props-function returns, appended: :extra 1 ...
 )
```

`:load` のないページでは、`:data` は nil です。`:key` はページのシンボルなので、同じページの2つのアドレスの間（`/p/1` → `/p/2`）ではインスタンスが残ります。`:initial-state` は1回だけ実行され、`:did-update` が新しいルートを受け取りました（確認済み）。`:load` を持つページで新しいデータがまだないときは、その間ページが `:loading` の要素に置き換えられるので、もう一度マウントされます。

ルーターがレイアウトの中に描画するもの：

| ページ | そのデータ | 描画されるもの |
|---|---|---|
| `:load` なし | | `(PAGE PROPS)` |
| `:load` あり | 読み込み中で、まだ何もない | `:loading`、なければ `nextel-loading-function` |
| `:load` あり | 失敗した | `:error`、なければ `nextel-error-function` |
| `:load` あり | 失敗のあと、もう一度読み込み中（Retry） | `:loading` |
| `:load` あり | ある（`nextel-reload` がもう一度読み込んでいる間も） | `:data` 付きの `(PAGE PROPS)` |
| どのルートにも一致せず、`nextel-not-found` が nil | | `""`（中身が空のレイアウト） |

<a id="load"></a>
#### `:load`

- ルーターの描画中、キー `(nextel PAGE PARAMS QUERY)` のデータがまだ読み込まれていないときに、ルートを引数に呼ばれます。
- `(RESOLVE REJECT)` を引数とする関数を返します。`nextel-request`、`react-fetch-async`、`react-sleep`、`react-all`、`react-race`、または自分で書いた lambda です。**`react-async` のタスクはこれに当たりません**。ルーターの描画が失敗します（`react-render-error`、`Invalid function: #s(react-task ...)`）。包んでください。`(react-race (list (react-async ...)))` なら動きます。
- resolve した値が `:data`（`(nextel-data SELF)`）になります。reject した値が `:error` の ERROR になります（`nextel-request` では `(:status N :message TEXT)`）。
- データはキーごとに保存されます（`react-query`）。ページ、パラメータ、クエリが同じアドレスに戻ると、ページはすぐに表示され、何も読み込みません。クエリ文字列が違えば別のキーなので、もう一度読み込みます。
- [`nextel-stale-ms`](#nextel-stale-ms)（60 秒）より古いデータは、ルーターがそのアドレスに戻ってきたときにもう一度読み込まれます。読み込みはバックグラウンドで行われ、その間ページは手元のデータを表示し（`:loading` にはなりません）、`:load` がもう一度呼ばれます。同じアドレスでもう一度描画しても、何も読み込みません。データの元が変わったあとは、[`nextel-reload`](#nextel-reload) を呼びます。

<a id="loading-and-error"></a>
#### `:loading` と `:error`

- `:loading` は、最初の読み込みの間と、失敗のあとにもう一度読み込む間に表示されます。
- `:error` は、ルート、reject された値、RETRY を受け取ります。`(funcall RETRY)` はそのキーを古い（stale）ものとし、もう一度読み込みます（その間は `:loading`）。
- どちらもページのコンポーネントではなく、ページの代わりに置かれる要素です。ページにはまだインスタンスも state もありません。

<a id="head"></a>
#### `:head`

- ページが表示されている間、ルーターが描画するたびに呼ばれます。`:load` を持つページでは、データが揃ってからだけ、そのデータを引数に呼ばれます。`:load` のないページでは常に、DATA を nil として呼ばれます。
- タイトルは `(funcall nextel-title-function TITLE)` です。ページに `:head` がないとき、データの読み込み中、`:head` が nil を返したときは、TITLE は nil です。デフォルトの `nextel-title-function` はそれを `""` にします。
- `<meta>`：`:description` が `("description" . TEXT)` になり、続いて `:meta` の各 `(NAME . CONTENT)` が、`react-set-meta` を通して設定されます。設定されるのはタイトルか meta が変わったときだけで、**削除されることはありません**。あるページが設定した `og:url` は、それを設定しない次のページにも残ります（確認済み。Chrome で、作例の `Item 1` の description がその 404 ページに残りました）。`react-set-meta` に nil の CONTENT を渡すと1つ削除されるので、`:meta '(("og:url" . nil))` で消せます（react.el の説明によります。ブラウザでは確かめていません）。

<a id="nextel-layout"></a>
### `(nextel-layout NAME &rest SPEC)` — マクロ

`(react-define-component 'NAME ,@SPEC)` で、それ以上のことはしません。pages/_layout.el のレイアウトはすべてのページを囲み、ページからページへ移ってもマウントされたままです。その props は `(:route ROUTE :children (PAGE-ELEMENT))` です。ページは `(react-props self :children)` で描画します。レイアウトは1つで、入れ子のレイアウトはありません。以下の設定（読み込み時の `setq`）は、pages/_layout.el に置くとよいでしょう。Parens もそうしています。

<a id="nextel-loading-function"></a>
### `nextel-loading-function` — 変数

`(lambda (_route) "")`。ROUTE を引数とする関数で、`:loading` のないページの読み込み中に表示する要素を返します。

<a id="nextel-error-function"></a>
### `nextel-error-function` — 変数

`(ROUTE ERROR RETRY)` を引数とする関数で、`:error` のないページの `:load` が失敗したときに表示する要素を返します。デフォルトは、`(plist-get ERROR :message)` か ERROR そのものと、Retry ボタンを表示します。

```html
<div class="nextel-error"><p>bad</p><button type="button">Retry</button></div>
```

<a id="nextel-title-function"></a>
### `nextel-title-function` — 変数

`(lambda (title) (or title ""))`。TITLE（`:head` のタイトル、または nil）を引数とする関数で、文書のタイトルを返します。Parens では `(lambda (part) (if part (concat part " - Parens") "Parens"))` です。

<a id="nextel-page-props-function"></a>
### `nextel-page-props-function` — 変数

nil、または plist を返す ROUTE の関数です。その plist は、すべてのページが `:key :route :data` のあとに受け取る props になります（この3つは上書きできません）。ページの描画時に呼ばれます。返す値が変わったあとは、[`nextel-refresh`](#nextel-refresh) を呼びます（確認済み。新しい値がページに届くのはそのときだけです）。

<a id="route-plist"></a>
### ルート

plist で、ページとレイアウトの `:route` prop です。

| キー | 値 | 例（`#/item/a%20b?x=1&y=%E3%81%82&x=2`） |
|---|---|---|
| `:page` | ページのシンボル。どのパターンにも一致しなければ `nextel-not-found` | `Item` |
| `:pattern` | 一致したパターン。一致しなければ nil | `"/item/[id]"` |
| `:path` | アドレスにあるとおりのパス。デコードしません | `"/item/a%20b"` |
| `:params` | plist。キーワード → デコードした文字列（`[...name]` では文字列のリスト）。パラメータのないパターンでは nil | `(:id "a b")` |
| `:query` | デコードした文字列の alist。順序どおりで、重複も残し、`+` は空白として読みます | `(("x" . "1") ("y" . "あ") ("x" . "2"))` |

末尾にスラッシュのあるパスは、スラッシュのないパターンに一致します（`/watch/` は `/watch`）。空のパスは `/` です。

<a id="nextel-route"></a>
### `(nextel-route)` → ルート

ルーターが最後に描画したルートです。マウントする前は nil です。

<a id="nextel-param"></a>
### `(nextel-param THING KEY)` → 文字列、文字列のリスト、または nil

THING のパラメータ KEY（キーワード。`:id`）です。THING はルートか、ページのインスタンス（SELF。その `:route` prop を使います）です。

<a id="nextel-query"></a>
### `(nextel-query THING NAME)` → 文字列または nil

THING（ルートか、ページのインスタンス）のクエリにある、NAME の最初の値です。**NAME は文字列**（`"v"`）で、キーワードではありません。値は文字列です（30 ではなく `"30"`）。

<a id="nextel-data"></a>
### `(nextel-data SELF)` → データ

`(react-props SELF :data)`。ページの `:load` が resolve した値です。

<a id="nextel-define-routes"></a>
### `(nextel-define-routes ROUTES &rest OPTIONS)`

ROUTES は `((PATTERN . PAGE) ...)`、OPTIONS は `:layout SYMBOL :not-found SYMBOL` です。[`nextel-routes`](#nextel-routes)（[`nextel-pattern<`](#nextel-pattern-lessp) で並べ替えたもの）、[`nextel-layout`](#nextel-layout-variable)、[`nextel-not-found`](#nextel-not-found) を設定します。呼ぶのは routes.el で、あなたではありません。

<a id="nextel-start"></a>
### `(nextel-start SELECTOR)`

`(react-mount '(nextel-router) SELECTOR)`。routes.el が最後に、[`nextel-mount-selector`](#nextel-mount-selector) を渡して呼びます。

<a id="nextel-router"></a>
### `nextel-router` — コンポーネント

アドレスを監視し（`react-location-watch`）、それを解決し、`(LAYOUT (:route ROUTE) PAGE-ELEMENT)` か、ページの要素だけを描画し、タイトルと meta を設定し、[`nextel-navigate-functions`](#nextel-navigate-functions) を実行します。インスタンスは1つで、`nextel-start` がマウントします。

<a id="nextel-resolve"></a>
### `(nextel-resolve PATH &optional SEARCH)` → ルート

PATH（`"/item/7"`）とクエリ文字列 SEARCH（`"?t=30"`。`?` はあってもなくても構いません）のルートを、`nextel-routes` に照らして求めます。最初に一致したものが勝ちます。`nextel-not-found` が `NF` のとき、`(nextel-resolve "/nowhere" "")` は `(:page NF :pattern nil :path "/nowhere" :params nil :query nil)` です。

<a id="nextel-routes"></a>
### `nextel-routes`、<a id="nextel-layout-variable"></a>`nextel-layout`、<a id="nextel-not-found"></a>`nextel-not-found` — 変数

`nextel-define-routes` が設定したものです。順に、試す順序に並んだ `((PATTERN . PAGE) ...)`、レイアウトのシンボルまたは nil、404 ページのシンボルまたは nil です。

<a id="nextel-stale-ms"></a>
### `nextel-stale-ms` — 変数

60000。読み込んだページのデータが新しいとみなされる時間（ミリ秒）です。ルーターがあるアドレス（ページ、パラメータ、クエリのいずれかが、最後に描画したアドレスと異なるもの）に来たとき、そのデータを読み込んだのがこの時間より前なら、データをバックグラウンドでもう一度読み込みます（そのキーの `react-invalidate`）。ページは手元のデータを表示し続け、そのあと新しいデータで描画します。nil なら、古さを理由に読み込み直すことはありません（もう一度読み込むのは `nextel-reload` と再試行だけです）。ルーターは各読み込みの時刻を自分で記録します。`react-query` 自身の `:stale-ms` が古さを見るのは、コンポーネントがキーを初めて読むときだけで、ルーターは一度読んだキーをすべて読み続けるからです。（v0.1.0：効果なし。）

<a id="addresses-and-navigation"></a>
## アドレスとナビゲーション

<a id="nextel-href"></a>
### `(nextel-href PATTERN &rest PARAMS)` → 文字列

リンク用の、ページ PATTERN のアドレスです。PATTERN と PARAMS の [`nextel-fill`](#nextel-fill) を、`#` のあと（hash モード）か、`nextel-base-path` のあと（path モード）に付けたものです。

```elisp
(nextel-href "/item/[id]" :id "7" :t 30)   ; => "#/item/7?t=30"
(nextel-href "/")                          ; => "#/"
;; nextel-url-mode path, nextel-base-path "/app":
(nextel-href "/item/[id]" :id "7" :t 30)   ; => "/app/item/7?t=30"
(nextel-href "/")                          ; => "/app/"
```

PATTERN はパターン（角括弧を含む）で、埋めたあとのパスでは決してありません。`(nextel-href "/item/[id]" :id id)` と書き、`(nextel-href (concat "/item/" id))` とは書きません。後者はエンコードされません。

<a id="link"></a>
### `Link` — コンポーネント

`(Link (:href HREF PROP...) CHILD...)`。`:children` と `:key` 以外のすべての prop を持つ `<a>` です。hash モードでは、ブラウザがそれをたどります。path モードではさらに、ブラウザのナビゲーションを止めて `(nextel-navigate HREF)` を呼ぶ `:on-click` が付きます（確認済み。クリックするとホストに `(:url "/app/" :replace nil)` が伝わります）。描画結果は `<a href="#/x" class="c">go</a>` です。hash モードでは、素の `(a (:href (nextel-href ...)))` でも動きます。path モードでは、ブラウザがページを新たに読み込んでしまいます。

<a id="nextel-navigate"></a>
### `(nextel-navigate HREF &optional REPLACE)`

`(react-navigate HREF REPLACE)`。新しい履歴項目を作ります。REPLACE があれば、現在の項目を置き換えます。ページのオリジンの中ではページはそのままで、ルーターが新しいアドレスを受け取ります。別のオリジンは読み込まれます。HREF は `nextel-href` が返すものです。

<a id="nextel-go"></a>
### `(nextel-go PATTERN &rest PARAMS)`

`(nextel-navigate (nextel-href PATTERN PARAMS...))`。`(nextel-go "/item/[id]" :id "z" :t 3)` は、ホストに `(:url "#/item/z?t=3" :replace nil)` を伝えます。REPLACE はありません。置き換えるには `nextel-navigate` を使います。

<a id="nextel-navigate-functions"></a>
### `nextel-navigate-functions` — 変数

ROUTE を引数とする関数のリストです。パスかクエリが前回と異なるアドレスを描画したあと、ルーターが呼びます。最初の描画のときも、クエリだけが変わったときも呼ばれます。`:load` を持つページでは、`:loading` を表示する描画で1回だけ実行され、データが来たときにはもう実行されません。ルーターはこれらを `dolist` で呼びます（2026-11-16 の wasmacs の修正までは、ページの Emacs はフックを実行しませんでした）。追加は `add-hook` か `push` で行います。用途：先頭へのスクロール、ドロワーを閉じる、ページビューを数える。

<a id="nextel-refresh"></a>
### `(nextel-refresh)`

`(react-refresh 'nextel-router)`。ルーターを、それとともにレイアウトとページを、`nextel-page-props-function` がいま返すもので、もう一度描画します。何も読み込みません。

<a id="nextel-reload"></a>
### `(nextel-reload)`

`(react-invalidate '(nextel))`。すべてのページのデータが古く（stale）なり、ルーターがマウントしてから読んだすべてのキーが、すぐにもう一度読み込まれます（以前に訪れたページも、クエリ文字列ごとに読み込まれます。確認済み：`/item/a` と `/item/a?x=1` を訪れたあとでは、読み込みが2回）。表示中のページは、新しいデータが来るまで手元のデータを保ちます。そこで失敗すると `:error` を表示します。ページが読み込むものを変えたリクエストのあとに呼びます。

<a id="nextel-url-mode"></a>
### `nextel-url-mode` — 変数

`hash`（デフォルト）か `path`。[表](#mental-model)を参照してください。routes.el が実行される前に設定します（それより前に読み込むスクリプトか、pages/_layout.el で）。

<a id="nextel-base-path"></a>
### `nextel-base-path` — 変数

`""`。path モードで、アプリケーションが置かれるパスです（`"/app"`。末尾のスラッシュなし）。すべての href と API の URL の前に付けられ、照合の前にアドレスから取り除かれます。その下にないアドレスは、全体のまま照合されます。

path モードでは、サーバーはページのすべてのアドレスに index.html で答えなければなりません。serve-project.sh は、ファイルでないパスには 404 で答えます。ただし server.el が `app-server-page-function` を設定していれば別で、`(setq app-server-page-function (lambda (_path) (list :status 200)))` とすると `/item/1` に index.html を送ります（curl で確認済み）。index.html のスクリプトの `src` は相対なので、`/item/1` ではブラウザがそれを `/item/` の下として解決します。そのようなページには `<base href="/">`（またはベースパス）を与えるか、`src` を絶対パスにします（HTML の規則から推論したもので、ブラウザでは試していません）。API の URL は `BASE/api/...` です。serve-project.sh が server.el に送るのは、`/api/` で始まるパスだけです。

<a id="patterns"></a>
## パターン

nextel-route.el です。ページ、サーバー、ルート表の書き出しが同じ関数を使います。

<a id="nextel-pattern-of-file"></a>
### `(nextel-pattern-of-file FILE)` → パターン

FILE は pages/ からの相対パス、api/ ではプロジェクトからの相対パスです。`"index.el"` → `"/"`、`"blog/[slug].el"` → `"/blog/[slug]"`、`"api/feed/index.el"` → `"/api/feed"`。

<a id="nextel-match"></a>
### `(nextel-match PATTERN PATH)` → plist、t、または nil

| 呼び出し | 結果 |
|---|---|
| `(nextel-match "/" "/")` | `t`（一致、パラメータなし） |
| `(nextel-match "/watch" "/watch/")` | `t` |
| `(nextel-match "/watch" "/Watch")` | `nil` |
| `(nextel-match "/channel/[id]" "/channel/UC%E3%81%82")` | `(:id "UCあ")`（UTF-8 としてデコード） |
| `(nextel-match "/x/[id]" "/x/a%2Fb")` | `(:id "a/b")` |
| `(nextel-match "/channel/[id]" "/channel/a/b")` | `nil` |
| `(nextel-match "/docs/[...path]" "/docs/a/b")` | `(:path ("a" "b"))` |
| `(nextel-match "/docs/[...path]" "/docs")` | `nil`（少なくとも1セグメント） |
| `(nextel-match "/docs/[...path]/edit" "/docs/a/edit")` | `nil`（`[...]` は最後のみ） |
| `(nextel-match "/café" "/caf%C3%A9")` | `t`（固定のセグメントはデコードして比較） |

<a id="nextel-pattern-rank"></a>
### `(nextel-pattern-rank PATTERN)` → リスト

セグメントごとに1つの数です。固定は 0、`[name]` は 1、`[...name]` は 2。`"/docs/[id]/[...rest]"` → `(0 1 2)`。

<a id="nextel-pattern-lessp"></a>
### `(nextel-pattern< A B)` → 真偽値

A が B より先に試されるなら non-nil です。ランクをセグメントごとに比べます（固定、パラメータ、キャッチオールの順）。両方にあるセグメントの範囲で一致する2つでは、長いほうが先です。それ以外はアルファベット順です。`(sort (list "/" "/a" "/[x]" "/a/b" "/a/[y]" "/[...all]" "/b") #'nextel-pattern<)` → `("/a/b" "/a/[y]" "/a" "/b" "/[x]" "/[...all]" "/")`。したがって `/item/new` は `/item/[id]` に勝ちます。

<a id="nextel-fill"></a>
### `(nextel-fill PATTERN PARAMS)` → 文字列

PATTERN の各 `[name]` を plist PARAMS から取って埋め、ほかの non-nil の PARAMS をその順にクエリ文字列にしたものです。各値は、文字列はそのまま、数は `number-to-string` で、シンボルはその名前で（`t` → `t`、`:kw` → `:kw`）、それ以外は `format "%s"` で文字列にし、そのあと `url-hexify-string` を通します（UTF-8。そのまま残るのは `A-Z a-z 0-9 - _ . ~` だけです）。`[name]` に対するリストは `/` でつなぎ、各部分をエンコードします（`[...name]` 用）。

| 呼び出し | 結果 |
|---|---|
| `(nextel-fill "/x/[id]" '(:id "a/b c"))` | `"/x/a%2Fb%20c"` |
| `(nextel-fill "/x/[id]" '(:id "あ"))` | `"/x/%E3%81%82"` |
| `(nextel-fill "/x/[id]" '(:id 42))` | `"/x/42"` |
| `(nextel-fill "/x/[id]" '(:id ("a" "b")))` | `"/x/a/b"` |
| `(nextel-fill "/x" '(:q "a b&c=d" :n 0 :s "" :b t :k :kw :l (1 2) :z nil))` | `"/x?q=a%20b%26c%3Dd&n=0&s=&b=t&k=%3Akw&l=%281%202%29"` |
| `(nextel-fill "/x" '(:a 1 :a 2))` | `"/x?a=1&a=2"` |
| `(nextel-fill "/x/[id]" '(:id ""))` | `"/x/"`（`/x/[id]` はこれに一致しません） |
| `(nextel-fill "/x/[id]" '(:id nil))` | エラー `/x/[id] needs :id` |

<a id="requests"></a>
## リクエスト

<a id="nextel-request"></a>
### `(nextel-request METHOD PATTERN &rest OPTIONS)` → awaitable

API のルート PATTERN（`"/api/items/[id]"`）が、METHOD（`"GET"`、`"POST"`、...。与えたとおりに送られます）に答えるものです。OPTIONS：

| オプション | |
|---|---|
| `:KEY VALUE` | PATTERN の `[key]` を埋めます。それ以外はクエリ文字列になります（[`nextel-fill`](#nextel-fill) の規則）。 |
| `:body DATA` | `print-length` と `print-level` を nil にして、`(prin1-to-string DATA)` として送られます。`:body nil` なら本文（body）は `"nil"` です。`:body` がなければ本文はありません。 |
| `:sends TYPE` | `nextel-request` を呼んだときに DATA が検査されます。不正なら、すぐに `nextel-type-error` をシグナルし（`POST /api/items body.id is required`）、何も送りません。 |
| `:returns TYPE` | 答えが検査されます。不正な答えはリクエストを失敗させます。 |

`:body`、`:sends`、`:returns` は、クエリのパラメータにはできません。ヘッダーは何も設定しません（Content-Type もありません）。URL は、hash モードでは文書からの相対の `api/...`、path モードでは `BASE/api/...` です。`(nextel-request "POST" "/api/items/[id]" :id "a b" :q "x")` は `api/items/a%20b?q=x` を fetch します。

値は `(RESOLVE REJECT)` を引数とする関数で、呼ばれるまで何も送りません。呼ぶのは、`react-async` の中の `react-await`、ページの `:load`、または `funcall` です。呼ばれると次のようになります。

| 応答 | 結果 |
|---|---|
| 2xx で、テキストを Lisp として読めた（`read-from-string`、その最初のデータ） | それで resolve します。`:returns` で検査されます |
| 2xx で、テキストが読めない（`""`） | nil で resolve します（`:returns` が nil を断るなら失敗） |
| 2xx で、`:returns` の型でない | `(:status nil :message "GET /api/items/[id].count: expected integer, got \"3\"")` で reject します |
| 2xx 以外 | `(:status 404 :message "No such item")` で reject します。メッセージは、本文（body）が文字列として読めればそれ、そうでなければ `"HTTP 404"` です |
| 応答なし（ネットワーク） | `(:status nil :message TEXT)` で reject します。TEXT は、ホストの fetch が言ったこと（`react-fetch` の `:catch`）です |

つまり `:status` が nil になるのは、答えは来たが `:returns` の型ではなかったときか、答えが来なかったときです。

`react-async` の中で両方の種類の失敗を捕まえる例（[作例](#worked-example)から）：

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

reject は、`react-await` にエラー `(react-async-error (:status 404 :message "No such API: /api/x"))` として届きます。plist は `(cadr failure)` です。

**通信の形式**は、行きも帰りも JSON ではなく、print した Lisp のデータです。レコードは plist で、plist のまま送られます：`(:id "1" :title "Milk")`。serve-project.sh は `Content-Type: application/x-emacs-lisp; charset=utf-8` で答えます。エラーの本文（body）は print した文字列で、引用符付きの `"No such item"` です。

<a id="schemas"></a>
## スキーマ

nextel-schema.el で、両側が読み込みます。定義は shared/ に置きます。

<a id="nextel-defschema"></a>
### `(nextel-defschema NAME [DOC] FIELD...)` — マクロ

```text
FIELD := (FIELD-NAME TYPE)
       | (FIELD-NAME TYPE :required t)
TYPE  := string | integer | number | boolean | symbol | keyword | any
       | SCHEMA-NAME
       | (member VALUE...) | (list-of TYPE) | (vector-of TYPE) | (or TYPE...)
```

| 型 | 受け入れるもの |
|---|---|
| `string` | `stringp` |
| `integer` | `integerp`（1.5 は不可） |
| `number` | `numberp` |
| `boolean` | `t` か `nil` |
| `symbol` | `symbolp`（キーワードも） |
| `keyword` | `keywordp` |
| `any` | 何でも |
| スキーマの名前 | そのスキーマの plist（後述） |
| `(member VALUE...)` | そのどれかと `equal` な値：`(member live upcoming)`、`(member t :false)` |
| `(list-of TYPE)` | すべての要素が TYPE であるリスト |
| `(vector-of TYPE)` | すべての要素が TYPE であるベクタ |
| `(or TYPE...)` | いずれかの型の値 |

スキーマの値とは、次のものです。偶数長のリストであること。どのキーもフィールドを指すキーワードであること（そうでなければ `no field :nick in p-person`）。値が non-nil のフィールドはすべてその型であること。`:required` のフィールドはすべて non-nil であること。**nil は「ない」を意味します**。フィールドは省いても nil でも構いません。`:required` のフィールドは nil にできません。`boolean` のフィールドは、ないとき偽です。キーの順序は問いません。スキーマは、あとで定義されるスキーマを名前で参照できます。型は、値を検査するときに探されます。

`(nextel-defschema demo-item "An item of the list." (id string :required t) (title string :required t) (done boolean))`（[作例](#worked-example)のもの）は次を定義し、`demo-item` を返します。

| 定義されるもの | 動作 |
|---|---|
| `(make-demo-item &rest FIELDS)` | `(nextel-check 'demo-item FIELDS)`。与えたとおりの plist か、`nextel-type-error`。デフォルト値も並べ替えもありません。 |
| `(demo-item-p VALUE)` | `(nextel-type-p 'demo-item VALUE)` |
| `(demo-item-id RECORD)`、`demo-item-title`、`demo-item-done` | `defsubst`：`(plist-get RECORD :id)`、... |

これらはグローバルな関数名です。`demo-item` に `by-id` というフィールドがあると、同じ名前のあなたの関数を上書きして `demo-item-by-id` を定義し、あなたの関数もまたそれを上書きします。形の正しくないフィールドは、展開時に失敗します：`nextel-defschema bad: a field is (NAME TYPE [:required t]), not (id)`。同じ NAME をもう一度定義すると、置き換えられます。

<a id="nextel-check"></a>
### `(nextel-check TYPE VALUE &optional WHERE)` → VALUE

VALUE が TYPE のものなら VALUE を返し、そうでなければ `nextel-type-error` をシグナルします。そのデータは 1 つの文字列で、`WHERE: expected TYPE, got VALUE`、`WHERE is required`、`WHERE: no field KEY in SCHEMA` のいずれかです。WHERE の既定値は型の名前です。フィールドでは `.FIELD` が、要素では `[INDEX]` が付け加わります。VALUE は `print-length` 4、`print-level` 2 で表示されます。確認済みのメッセージを、スキーマ `p-item`（フィールドは `id` が必須、`count` が integer、`tags` が `(list-of string)`、`vec` が `(vector-of integer)`、`kind` が `(member book film)`、`either` が `(or integer string)`、`owner` が `p-person`、`people` が `(list-of p-person)`）と `p-person`（`name` が string で必須）で示します。

| VALUE（断りがなければ TYPE は `p-item`） | メッセージ |
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
| `((:id "a") (:id 2))`、TYPE は `(list-of p-item)` | `(list-of p-item)[1].id: expected string, got 2` |
| `3`、TYPE は `string`、WHERE は `"title"` | `title: expected string, got 3` |

elisp-next が渡す WHERE は、サーバーでの `:accepts` では `"body"`（`body.title is required`）、`:returns` では `"METHOD PATTERN"`（`GET /api/items/[id].count: ...`）、`:sends` では `"METHOD PATTERN body"`（`POST /api/items body.id is required`）です。

型でもスキーマでもない TYPE は、`nextel-type-error` ではなく、ただの `error` になります：`No type or schema named unknown-type`、`Not a type: (frob x)`。

<a id="nextel-type-p"></a>
### `(nextel-type-p TYPE VALUE)` → t または nil

捕まえるのは `nextel-type-error` だけです。未知の TYPE では、やはり `No type or schema named ...` をシグナルします。

<a id="nextel-schema-fields"></a>
### `(nextel-schema-fields NAME)` → フィールドまたは nil

形は `((FIELD TYPE :required BOOL) ...)` です。`(nextel-schema-fields 'p-person)` → `((name string :required t))`。未知の名前では nil です。

<a id="nextel-type-error"></a>
### `nextel-type-error` — エラーシンボル

エラー条件（conditions）は `(nextel-type-error error)`、メッセージは `"Not of the expected type"` です。データは `(MESSAGE)` です。表示には `(cadr ERR)` を使います。`error-message-string` では `Not of the expected type: "string: expected string, got 3"` になります。

<a id="server"></a>
## サーバー

nextel-server.el。elisp-studio の app-server.el のもとで動きます。

<a id="nextel-server-load"></a>
### `(nextel-server-load &optional DIRECTORY)` → ルート

DIRECTORY の既定値は `app-server-project-directory`（なければ `default-directory`）です。この関数は次のことをします。

1. `DIRECTORY/shared/` のすべての `*.el` をパスの順に読み込みます（そのディレクトリがあれば）。以下の手順でも同じですが、隠しファイルと隠しディレクトリ（名前が `.` で始まるもの）は除きます。
2. [`nextel-server-routes`](#nextel-server-routes) を空にします。
3. api/ の補助ファイル（パスの要素が `_` で始まるもの）をパスの順に読み込みます。
4. api/ のそれ以外の `*.el` をすべて、そのパターン（ファイル名から `nextel-pattern-of-file` で求めたもの）とともに記録します。最も具体的なものが先です。
5. 遅延読み込み（後述）でなければ、それらのファイルを 1 つずつ、そのパターンを現在のパターンにして読み込みます。こうしてファイルの `nextel-handle` 呼び出しがそのパターンのもとに登録されます。そのあとルートをパターンで並べ替えます（`nextel-pattern<`。1 つのファイルのメソッドは書かれた順）。
6. `app-server-handle` を `nextel-server-handle` の別名にします。
7. `nextel-server-routes` を返します。すべてのルート、または遅延読み込みのときは nil です。

ファイルは、その `.elc` がファイルより新しければ、そちらから読み込まれます（elisp-studio の `server/cgi/install.sh` が、配置する先で shared/ と api/ をコンパイルします。ほかにそれらを書き出すものはありません）。

**遅延読み込み。** [`nextel-server-lazy`](#nextel-server-lazy) か elisp-studio の `app-server-single-request` が non-nil のとき（後者は elisp-studio の `serve-cgi.el` が設定します。CGI はリクエストごとに Emacs を 1 つ起動するからです）、手順 5 は行いません。`nextel-server-handle` は、リクエストが来たときに、そのリクエストに答えるファイルを読み込み、api/ のほかのファイルは読み込みません。答えは、404 と 405 も含めて同じです。リクエストがほかの場所から必要とするものは、常に読み込まれる shared/ か補助ファイルに置きます。さくらのレンタルサーバー（Emacs 27.2）で Parens（ルートのファイルは 4 つ）を使って測りました。elisp-next、`shared/`、`api/` をコンパイルすれば、1 リクエストは Emacs の中で 7 ms です。これほど少なく小さなファイルでは、全部を読み込んでも 1 つ読み込むのとほぼ同じです（差は 1 ms 以内）。遅延読み込みが効いてくるのは `api/` が大きくなってからで、コンパイル済みのファイルはすぐに効きます（nextel-schema.el と nextel-route.el：ソースからだと 2.3 ms、コンパイル済みなら 0.3 ms）。

サーバーはディレクトリを自分で読みます（routes.el は使いません）。新しい api/ ファイルや名前を変えた api/ ファイルは、`nextel-server-load` がもう一度動いたとき、つまり次にサーバーを起動したときにルートになります。elisp-studio の `--native-server` は、サーバーが読み込んだファイルが保存されるとサーバーを再起動します。serve-project.sh では、自分で再起動してください。

<a id="nextel-handle"></a>
### `(nextel-handle METHOD &rest SPEC)` → nil

api/ のファイルの中でだけ使います（そうでなければ `nextel-handle belongs in a file of api/, loaded by ‘nextel-server-load’`）。METHOD は大文字の文字列で、`equal` で比べます（`"GET"`、`"POST"`、`"PUT"`、`"PATCH"`、`"DELETE"`。HEAD は GET から作られません）。SPEC は次のとおりです。

| キー | |
|---|---|
| `:handler` | 必須です（`GET /api/broken has no :handler`）。REQUEST を受け取る関数です。 |
| `:accepts TYPE` | 最初に本文（body）を検査します。違っていればメッセージを付けて 400 で答え、ハンドラは実行しません。空の本文（body）は nil で、これも検査します。 |
| `:returns TYPE` | 答えを検査します。違っていれば 500 `The server's answer is wrong: MESSAGE` で答え、`nextel-server: GET /api/x answered wrongly: MESSAGE` とログに書きます。`app-server-defer` による答えは、届いたときに検査します。 |

REQUEST は `(:method "GET" :path "/api/items/1" :params (:id "1") :body DATA)` です。`:path` はクエリ文字列を除いたもの（末尾のスラッシュは残ります）、`:params` はパラメータのないパターンでは nil、`:body` は `app-server-data` が読んだデータです。クエリは `(app-server-parameter "q")` で得ます。

ハンドラが返すのは、Lisp のデータ（print した形で送られ、200）か、あとで答えるための `(app-server-defer (lambda (respond fail) ...))` です。あるいはシグナルします：`(app-server-refuse MESSAGE [STATUS])`（STATUS の既定値は 400）、`error`、またはそれ以外のもの（表を参照）。1 つのファイルに同じメソッドの `nextel-handle` が 2 つあれば、最初のものが勝ちます。

<a id="nextel-server-handle"></a>
### `(nextel-server-handle METHOD PATH BODY)`

`nextel-server-load` のあとの `app-server-handle` の中身です。記録したファイルを順に（最も具体的なものから）試します。PATH に合うファイルは、まだ読み込まれていなければ読み込み、パターンにルートがある最初のファイルが答えます。PATH に合う最も具体的なパターンが答え（試す順で最初のもの。同じ 1 つのパターンを持つ 2 つのファイルのルートは合わせて数えます）、そのパターンが扱わない METHOD は 405 になります。より具体的でないファイルがその METHOD を扱う場合でもそうです。`api/things/new.el` が GET だけを扱うとき、`DELETE /api/things/new` は、`api/things/[id].el` が DELETE を扱っていても 405 です。（v0.1.0 では、次に合うファイルへ進んでいました。）答えは次のとおりです（確認済み。テキストは送られるとおり）。

| 場合 | ステータス | 本文（body） |
|---|---|---|
| ハンドラの答え | 200 | `(:id "1" :title "Milk")` |
| どのパターンにも合わない | 404 | `"No such API: /api/nothing"` |
| 合うパターンのうち最も具体的なものに METHOD がない | 405 | `"DELETE is not allowed at /api/items"` |
| BODY が Lisp のデータでない | 400 | `"The request is not Lisp data"` |
| BODY に、サーバーの Emacs が知らないシンボルが書かれている | 400 | `"The request names something unknown: :surprise"` |
| BODY が `:accepts` の型でない | 400 | `"body.title: expected string, got 3"` |
| `(app-server-refuse "No such item" 404)` | 404 | `"No such item"` |
| ハンドラが `error` をシグナルする | 400 | `"Something went wrong: 42"` |
| それ以外のエラーをシグナルする | 400 | そのメッセージ。serve-project.sh のもとでのように `app-server-explain-errors` が nil のときは `"The request could not be answered"` |
| 答えが `:returns` の型でない | 500 | `"The server's answer is wrong: GET /api/x.id: expected string, got 1"` |
| 遅延した答えで `(funcall fail "busy" 503)` | 503 | `"busy"` |
| 遅延して、答えが来ない（ネイティブのサーバー） | `app-server-deferred-timeout`（30 秒）のあと 504 | `"The server did not answer in time"`（app-server.el を読んで確認。実行はしていません） |

BODY の最初のデータのあとのテキストは無視されます。本文（body）に含められるのは、文字列、数、リスト、ベクタ、そしてサーバーがすでに知っているシンボルだけです。知っているシンボルとは、読み込まれた Lisp が使う名前（スキーマのキーワードや `member` の値はこれに当たります）と、nil と t です。

<a id="nextel-server-routes"></a>
### `nextel-server-routes` — 変数

試す順に並んだ `((PATTERN METHOD . SPEC) ...)` です。SPEC は `nextel-handle` に渡した plist です。遅延読み込みでは、それまでに読み込んだファイルのルートを持ちます。

<a id="nextel-server-lazy"></a>
### `nextel-server-lazy` — 変数

既定値は nil です。api/ のすべてのファイルを最初に読み込むので、どれかに誤りがあればサーバーの起動時に（スタジオ（elisp-studio）ではファイルを保存したときに）わかります。non-nil なら `app-server-single-request` と同じです（前述）。`nextel-server-load` の前に設定してください。

<a id="running-the-server"></a>
### 動かし方

```sh
../elisp-studio/tools/serve-project.sh DIRECTORY PORT     # PORT defaults to 8018
```

ネイティブの Emacs が DIRECTORY のファイルを 127.0.0.1:PORT で配信し、`/api/` で始まるパスを server.el（`.data/server.elc` にバイトコンパイルされます）に渡します。`app-server-read` と `app-server-write` はファイルを `DIRECTORY/.data/` に置きます。server.el、`*.sh`、`.` で始まる名前は配信しません。`Origin` がほかのサイトであるリクエストは 403 `"requests from other sites are refused"` になります。ページ自身のオリジンを持つリクエストや、オリジンのないリクエスト（curl）には答えます。ダウンロードした elisp-studio のプロジェクトには、同じことをする `./run.sh [PORT]` があります。Ctrl-C で止めます（または Emacs のプロセスを kill します）。

<a id="routes-writer"></a>
## ルート表の書き出し

nextel-build.el。編集に使っている Emacs、elisp-studio の Emacs、またはバッチの Emacs で動きます。

<a id="nextel-write-routes"></a>
### `M-x nextel-write-routes`, `(nextel-write-routes &optional ROOT)` → 変更したファイル

```text
M-x load-file RET vendor/elisp-next/lisp/nextel-build.el RET   once per session (the project's copy)
M-x nextel-write-routes                                        after adding, removing or renaming a page
```

ROOT の既定値は、カレントバッファのファイルのプロジェクト（または `default-directory`）です。プロジェクトの外ではユーザーエラー `Not in a project with index.html and pages/` になります。routes.el と index.html を計算し、それぞれテキストが変わったときだけ書き出します。そのファイルを訪問しているバッファがあれば、そのバッファを通して書き（保存もします）、そのバッファに保存していない変更があれば失敗します（`index.html has changes that are not saved: save it, then write the routes`）。書き出したファイルを相対パスで返し（`("routes.el" "index.html")`、または nil）、`nextel: 2 pages, 2 API routes: wrote routes.el, index.html` か `nextel: 2 pages, 2 API routes, nothing changed` と表示します（404.el とレイアウトはページとして数えません）。

実行するとき：pages/ か shared/ のファイルを追加、削除、または名前変更したあと、ページの `(nextel-page NAME` やレイアウトの NAME を変えたあと、そして api/ ファイルを追加または削除したあと（変わるのは routes.el のコメントだけですが、`--check` は気づきます）。

<a id="nextel-routes-mode"></a>
### `M-x nextel-routes-mode` — グローバルマイナーモード

lighter は ` nextel`、グループは `nextel`、フックは `nextel-routes-mode-hook` です。オンのあいだは、プロジェクトの `pages/`、`api/`、`shared/` の下のファイルを保存するたびにルート表を書き出します。失敗はエラーではなく、メッセージ（`nextel: ...`）になります。保存せずに削除や名前変更をしたファイル（dired やシェルで）には `M-x nextel-write-routes` が必要です。

<a id="bin-nextel-routes"></a>
### `bin/nextel-routes`

```sh
vendor/elisp-next/bin/nextel-routes [DIRECTORY]           # write routes.el and index.html's scripts
vendor/elisp-next/bin/nextel-routes --check [DIRECTORY]   # exit 1 when they are not up to date
vendor/elisp-next/bin/nextel-routes --watch [DIRECTORY]   # write them whenever pages/, api/ or shared/ change
```

DIRECTORY（既定値は `.`。プロジェクトのサブディレクトリでも動きます）に `cd` して、`emacs --batch -Q -l BIN/../lisp/nextel-build.el -f COMMAND` を実行します。ですから、プロジェクトのコピーを実行してください。Emacs は `$EMACS`、なければ PATH 上の `emacs`、`/Applications/Emacs.app/...`、`/Applications/Emacs-takaxp/Emacs.app/...` のうち、起動できる最初のものです。フラグは最初に置く必要があります。終了ステータス：0 は完了。1 は `--check` が古い（stale）と判定した（`nextel: not up to date: routes.el, index.html; write them (M-x nextel-write-routes, bin/nextel-routes)`）。2 は未知のフラグ（`usage: nextel-routes [--check | --watch] [DIRECTORY]`）。127 は Emacs がない。255 は Lisp のエラー（メッセージとバックトレースは stderr へ）。npm では `"routes": "vendor/elisp-next/bin/nextel-routes"` です。

<a id="nextel-check-routes"></a>
### `(nextel-check-routes)` → 真偽値

バッチ用です。`default-directory` のプロジェクトを対象にし、`nextel: the routes are up to date` か、古い（stale）ファイルを表示し、バッチでは 0 か 1 で終了します。

<a id="nextel-watch-routes"></a>
### `(nextel-watch-routes)`

バッチ用で、戻りません。0.5 秒ごとに pages/、api/、shared/ の `*.el` ファイル（名前と更新時刻。隠しファイルは除く）を前回と比べ、変化があれば `nextel-write-routes` を呼びます。エラーは表示して（`nextel: pages/broken.el has no (nextel-page NAME ...)`）続行します。確認済み：新しいページが 1 秒以内に routes.el に入りました。Ctrl-C で止めます。

<a id="nextel-project-root"></a>
### `(nextel-project-root &optional FILE)` → ディレクトリまたは nil

FILE（または `default-directory`）の位置かそれより上にあって、`index.html` と `pages/` を持つ、最も近いディレクトリです。末尾にスラッシュが付きます。

<a id="nextel-read-project"></a>
### `(nextel-read-project ROOT)` → plist

ルート表の書き出しが元にするものです。`pages/{_layout,_a,About,index,quoted}.el`、`pages/_drafts/x.el`、`pages/blog/{index,404}.el`、`api/{_x,x}.el`、`shared/{z,sub/a}.el` を持つプロジェクトでは次のようになります。

```elisp
(:routes (("/blog/404" "Blog404" "blog/404.el") ("/About" "Upper" "About.el") ("/blog" "BlogIndex" "blog/index.el")
          ("/quoted" "'Quoted" "quoted.el") ("/" "Wrong" "index.el"))
 :layout "Frame" :not-found nil
 :api (("/api/x" "api/x.el"))
 :shared ("shared/sub/a.el" "shared/z.el")
 :page-scripts ("pages/_layout.el" "pages/_a.el" "pages/_drafts/x.el" "pages/About.el" "pages/blog/404.el"
                "pages/blog/index.el" "pages/index.el" "pages/quoted.el"))
```

（`"Wrong"`：pages/index.el には、本当のフォームより前のコメントに `;; Like (nextel-page Wrong ...)` がありました。`"'Quoted"`：pages/quoted.el には `(nextel-page 'Quoted` と書かれていました。どちらも誤りです。[落とし穴 5](#pitfalls) を参照してください。）

<a id="nextel-routes-text"></a>
### `(nextel-routes-text PROJECT)` → 文字列

PROJECT（`nextel-read-project` の plist）に対する routes.el のテキストです。[作例の routes.el](#example-routes) とまったく同じになります。

<a id="nextel-index-text"></a>
### `(nextel-index-text HTML PROJECT ROOT)` → 文字列

HTML（index.html のテキスト）の 2 つの領域を、[説明したとおり](#index-html)に埋めたものです。

<a id="nextel-mount-selector"></a>
### `nextel-mount-selector` — 変数

`"#app"`。routes.el の `nextel-start` の引数です。

<a id="nextel-routes-file"></a>
### `nextel-routes-file` — 変数

`"routes.el"`。ルート表の書き出しが書くファイルで、プロジェクトからの相対パスです。pages 領域の最後のスクリプトでもあります。

<a id="nextel-group"></a>
### `nextel` — カスタマイズグループ

`tools` の下にあり、`nextel-routes-mode` を含みます。

<a id="from-elisp-react"></a>
## elisp-react と app-server.el から

elisp-next のアプリケーションが、elisp-next 自身の関数のほかに使う関数です。完全なリファレンスは [elisp-react の README](https://github.com/modeverv/elisp-react#api)、[elisp-studio の README](https://github.com/modeverv/elisp-studio#a-server-side)、そして `lisp/react.el` と `lisp/app-server.el` の docstring です。

ページ側（react.el）：

| | |
|---|---|
| `(react-define-component NAME &rest SPEC)` | `:render (SELF)` は必須。`:initial-state (PROPS)` → state の plist。`:did-mount (SELF)`。`:did-update (SELF PREVIOUS-PROPS PREVIOUS-STATE)`。`:will-unmount (SELF)`。`:should-update (SELF PREVIOUS-PROPS PREVIOUS-STATE)` → nil ならスキップ。`:pure t`。`:did-catch (SELF ERROR)`。 |
| `(jsx FORM)` | バッククォートなしのマークアップ：`(TAG PROPS CHILD...)` または `(TAG CHILD...)`。PROPS はキーワードで始まるリスト。HTML タグ、`<>`、または**大文字で始まる**シンボルで始まるリストは要素です。それ以外は評価される Lisp です（その中のマークアップにはもう一度 `jsx` が必要）。 |
| `(react-props SELF &optional KEY)`, `(react-state SELF &optional KEY)`, `(react-set-state SELF &rest CHANGES)` | props、state、state を変えて再び描画。 |
| `(react-effect SELF KEY DEPS FUNCTION)` | 描画の中で使います。DEPS が変わったとき、描画のあとに FUNCTION を実行します。FUNCTION が返す関数が後始末をします。 |
| `(react-async BODY...)` → タスク, `(react-await AWAITABLE)` | 非同期のコード。失敗すると `react-async-error` をシグナルし、その `cadr` が reject の値です。`lambda`、`mapcar`、`with-temp-buffer` などの中では `react-await` を使えません。 |
| `(react-fetch-async URL &rest OPTIONS)` | 値がレスポンス `(:status :ok :url :redirected :headers :text)` である awaitable。 |
| `(react-all LIST)`, `(react-race LIST)`, `(react-sleep MS)` | awaitable（RESOLVE と REJECT を受け取る関数）。最初の 2 つはタスクも受け取ります。 |
| `(react-handler FUNCTION :prevent t ...)` | `preventDefault`、キー、スロットリングを指定できるリスナーの prop。 |
| `(react-location &optional PART)`, `(react-navigate URL &optional REPLACE)`, `(react-history-go DELTA)` | アドレス。ほかの場所への移動。 |
| `(react-set-title TEXT)`, `(react-set-meta NAME CONTENT)` | `:head` が使うもの。 |
| `(react-query SELF KEY LOADER &rest OPTIONS)`, `(react-invalidate PREFIX)`, `(react-query-set KEY DATA)` | `:load` の下にあるキャッシュ。キーは `(nextel PAGE PARAMS QUERY)` です。 |
| `(react-storage-get KEY &optional DEFAULT)`, `(react-storage-set KEY VALUE)` | localStorage。print できる Lisp データなら何でも保存できます。 |

サーバー側（app-server.el）：

| | |
|---|---|
| `app-server-project-directory` | プロジェクトのディレクトリ（server.el はここから読み込みます。`load-path` に入っています）。 |
| `app-server-data-directory` | `app-server-write` がファイルを置く場所（serve-project.sh のもとでは `.data/`）。 |
| `(app-server-read NAME &optional DEFAULT)`, `(app-server-write NAME VALUE)` | `DATA/NAME.eld` に置く Lisp の値（NAME は `A-Za-z0-9_-` からなる）。write はファイルを一度に置き換え、VALUE を返します。 |
| `(app-server-database &optional NAME)` | `sqlite-execute` と `sqlite-select` で使う SQLite データベース。 |
| `(app-server-data TEXT &optional DEFAULT)` | データとして読んだ本文（body）。評価はしません（nextel-server-handle が呼びます）。 |
| `(app-server-parameter NAME &optional DEFAULT)` | いま答えているリクエストの `?NAME=VALUE`。 |
| `(app-server-refuse MESSAGE &optional STATUS)` | エラーのステータスで答えます（既定値は 400）。 |
| `(app-server-defer FUNCTION)` | あとで答えるために、これを返します。FUNCTION は RESPOND（データ）と FAIL（メッセージ、ステータス）を受け取ります。 |
| `(app-server-fetch URL &rest OPTIONS)`, `(app-server-after SECONDS FUNCTION)` | 遅延した答えが待つもの。 |
| `app-server-explain-errors` | t ならエラーのテキストが答えになります。serve-project.sh のもとでは nil。 |
| `(app-server-respond METHOD PATH BODY &optional LATER HEADERS)` → `[STATUS TEXT HEADERS]` または nil | ホストが行うのと同じように 1 つのリクエストを処理します。テスト用。 |
| `app-server-page-function` | nil、または PATH を受け取る関数。ファイルではないパスについてこの関数が plist を返すと、serve-project.sh は index.html を送ります。`path` モードに必要です。elisp-next はこれを使いません。 |

<a id="testing"></a>
## アプリケーションのテスト

elisp-next 自身の `test/nextel-test.el` と同じく、両側を 1 つのネイティブの Emacs（`emacs --batch`）で動かします。[作例のテスト](#example-test)は次のことをします。

- serve-project.el と同じく、app-server.el を読み込み、`app-server-data-directory` を一時ディレクトリにし、`(app-server-use-project ROOT)` を呼び、server.el を読み込みます。
- `(app-server-respond METHOD PATH BODY nil)` → `[STATUS TEXT HEADERS]` でサーバーを呼びます。
- `react-testing-reset`、`(react-testing-location "#/")` でページを始め、index.html のすべての `<script type="text/emacs-lisp">` の `src` を順に `load` し（routes.el がアプリケーションをマウントします）、最後に `react-testing-flush` します。
- ページの fetch にサーバーの答えで応えます（`react-testing-requests`、`react-testing-answer-fetch STATUS TEXT`）。往復全体を通し、型は両端で検査されます。
- `(react-testing-location "#/item/1")` で移動し、`react-testing-find`、`react-testing-text`、`react-testing-html` で見て、`react-testing-input` と `react-testing-click` で操作し、タイトルと meta を `react-testing-told` から読みます（`("title" (:text "Milk - Demo"))`、`("meta" (:name "description" :content "Item 1"))`）。

`react-testing-time-passes` はタイマー（`react-set-timeout`、`react-sleep`）を発火させます。

<a id="pitfalls"></a>
## 規則と落とし穴

1. **接頭辞は `nextel-` です**。`next-` ではありません（`next-line`、`next-match` は Emacs のものです）。自分のコードには独自の接頭辞を付けます（`demo-`）。
2. **どのファイルも `-*- lexical-binding: t; -*-` で始めます。** これがないファイルについて、Emacs 31 は警告し（`Missing ‘lexical-binding’ cookie`）、動的束縛で評価します。
3. **ページや shared/ のファイルを追加、削除、名前変更したら、ルート表を書き出します**。コンポーネントの NAME を変えたあとも同じです：`M-x nextel-write-routes`、`nextel-routes-mode`、または `bin/nextel-routes`。routes.el にないページにはアドレスがありません。index.html にない shared/ のファイルは、ページに読み込まれません。CI では `bin/nextel-routes --check`。
4. **routes.el はコンポーネントを名前で指します。** ルート表を書き出さずに `(nextel-page OldName` を `NewName` に変えると、ルーターは未知の要素を描画します：`react: OldName is not a defined component; it is rendered as an unknown element <oldname> (a misspelled name, or a file loaded too late?)` と表示され、ページには `<OldName route="...">` が出ます。
5. **ルート表の書き出しは NAME をテキストとして読みます**。ファイルのどこであれ（コメントや文字列の中も含めて）、名前が続く最初の `(nextel-page `（または `(nextel-layout `）を使います。NAME はクォートせずに書きます（`(nextel-page 'Foo` と書くと routes.el に `'Foo` が入ります）。フォームを先頭に置き、その上のコメントではそれに触れないでください。
6. **コンポーネント名は大文字で始めます**（`HomePage`、`Layout`）。`jsx` が要素として扱うのは、大文字で始まるシンボル、HTML タグ、`<>` だけです。ルーター自体はどんなシンボルでも受け付けます。
7. **スキーマの関数はあなたの名前空間を共有します。** `nextel-defschema demo-item` は `make-demo-item`、`demo-item-p`、そしてフィールドごとに `demo-item-FIELD` を定義します。同じ名前の自分の関数は、黙って置き換えられるか、アクセサを置き換えます（バイトコンパイラが引数の数に気づくことはあります）。補助関数はその接頭辞の外で名付けます：`demo-item-by-id` ではなく `demo-find-item`。
8. **nil は「ない」ことです。** `:required` のフィールドは nil にできません。`boolean` の偽は、フィールドを省いた状態です。`(member nil ...)` は、ないことと区別できません。
9. **渡すのはキーワード、返るのは文字列。** `nextel-href`、`nextel-go`、`nextel-request`、`nextel-param` はキーワード（`:id`、`:v`）を受け取ります。`nextel-query` は文字列（`"v"`）を受け取ります。パラメータとクエリの値は文字列で返ります：`(string-to-number (nextel-query self "t"))`。
10. **`:load` は RESOLVE と REJECT を受け取る関数を返します**。`react-async` のタスクではありません（ルーターが失敗します）。タスクは `(react-race (list TASK))` で包みます。
11. **データはページ、パラメータ、クエリごとにキャッシュされます。** 新しいクエリ文字列では、もう一度読み込みます。再訪問では、データが `nextel-stale-ms`（60 秒）より古いときだけ、裏でもう一度読み込みます。データを変えたリクエストのあとは `nextel-reload` を呼びます（訪れたすべてのページを読み込み直します）。
12. **`:head` が設定した `<meta>` は残ります**。それを設定しない後続のページでも残ったままです。
13. **`:body`、`:sends`、`:returns` は `nextel-request` のクエリパラメータではありません**。それ以外のキーワードはすべてクエリパラメータです。
14. **`:sends` の失敗はその場でシグナルされます**（`nextel-type-error`、メッセージは `(cadr err)`）。サーバーや `:returns` の失敗は awaitable を通して届きます（`react-async-error`、plist は `(cadr err)`）。ユーザーの入力を送る場所では、両方を捕まえてください。
15. **server.el の `declare-function` の行は残します**（なければ起動のたびにコンパイラの警告が出ます）。また、server.el は `app-server-handle` を定義しません。
16. **フレームワークはプロジェクトのコピー（`vendor/elisp-next/`）から使います**。その nextel-build.el を読み込み、その `bin/nextel-routes` を実行します。1 つの Emacs セッションでは、ルート表の書き出しは最後に読み込んだコピーで動きます。別のプロジェクトでは、そのプロジェクトのコピーを `M-x load-file` してください。
17. **隠しファイルは読み込まれません。** サーバーとルート表の書き出しは、名前が `.` で始まるファイルとディレクトリをすべて除きます（バッファに保存していない変更があるあいだにできる Emacs のロックファイル `api/.#items.el` など）。v0.1.0 ではサーバーがそれらを読み込み、ロックファイルのせいで起動できませんでした。
18. **新しい api/ ファイルは、サーバーの次の起動でルートになります**。それより前ではありません。同じパターンの api/ ファイルが 2 つあってもエラーではなく、最初のものが勝ちます。
19. **ページが送るものは、サーバーが知っているデータでなければなりません。** サーバーの Emacs が一度も読んだことのないシンボルは、`:accepts` より前に断られます（400 `The request names something unknown: ...`）。shared/ のスキーマのキーワードや `member` の値なら問題ありませんが、自由な `symbol` や `any` のフィールドでは問題になります。
20. **ハンドラ内のエラーは 500 ではなく 400 です。** また serve-project.sh のもとでは、`error` か `user-error` でない限り、そのテキストは隠されます（`The request could not be answered`）。意図して断るときは、`app-server-refuse` とステータスを使います。
21. **shared/ は両側で動きます**。読み込み時に react.el も app-server.el も使えません。
22. **index.html の閉じマーカーは、それぞれ新しい行で始めます。**
23. **ハッシュモードが既定で、何も必要ありません**（静的ホスト、elisp-studio のプレビュー）。パスモードには、ページのすべてのアドレスに対して index.html を送るサーバー（serve-project.sh のもとでは `app-server-page-function`）、置き場所に合った `nextel-base-path`、深いパスからでも解決できるスクリプトの `src` が必要です。
24. **ルーターは `nextel-navigate-functions` を呼びます**。最初の描画時と、パスかクエリが変わるたび（クエリだけの変化でも）に、アドレスごとに 1 回、`:load` を持つページのデータが届く前に呼びます。
25. **特別なのは最上位の `pages/_layout.el` と `pages/404.el` だけです**。レイアウトは 1 つで、入れ子にはできません。
26. **HTTP メソッドは正確な文字列です**：`"get"` や `'get` ではなく `"GET"`。HEAD と OPTIONS は、ファイルが扱わない限り答えられません。
27. **複数のルートが必要とするものは、shared/ か api/ の補助ファイル（`api/_name.el`）に置きます**。`app-server-defjob` の呼び出しも同じです。elisp-studio の CGI（`app-server-single-request`）のもとでは、ルートのファイルは、そのパターンへのリクエストが来たときにだけ読み込まれます。そのため、`api/a.el` で定義した関数は `api/b.el` が答えるときには存在せず（`void-function` エラー）、ルートのファイルで定義したジョブは `job.sh` から見えません。

<a id="worked-example"></a>
## 作例

項目のリストです。`/` は項目を一覧し、1 つ追加します（POST）。`/item/ID` は 1 つを表示します（GET による `:load`）。`/api/items` と `/api/items/ID` はサーバーで答えます。以下のファイルはすべて、このまま動かしました。ルート表は `bin/nextel-routes` で書き出し、テストは通り（2/2）、`serve-project.sh` で配信し、Chrome で使いました（一覧、追加、項目のページ、エラー、404）。

```text
index.html  routes.el  server.el
pages/_layout.el  pages/index.el  pages/item/[id].el  pages/404.el
api/_store.el  api/items.el  api/items/[id].el
shared/types.el
test/demo-test.el
vendor/elisp-next/   (see "vendor/elisp-next" above)
```

`index.html`（ルート表を書き出す前）：

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

`shared/types.el`：

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

`api/_store.el`：

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

`api/items.el`：

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

`api/items/[id].el`：

```elisp
;;; [id].el --- GET /api/items/ID  -*- lexical-binding: t; -*-

(nextel-handle "GET"
  :returns 'demo-item
  :handler (lambda (request)
             (or (demo-find-item (plist-get (plist-get request :params) :id))
                 (app-server-refuse "No such item" 404))))

;;; [id].el ends here
```

`server.el`：

```elisp
;;; server.el --- the server side: the files of api/  -*- lexical-binding: t; -*-

(declare-function nextel-server-load "nextel-server")
(load (expand-file-name "vendor/elisp-next/lisp/nextel-server.el" app-server-project-directory) nil t)
(nextel-server-load)

;;; server.el ends here
```

`pages/_layout.el`：

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

`pages/index.el`：

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

`pages/item/[id].el`：

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

`pages/404.el`：

```elisp
;;; 404.el --- an address that no file of pages/ has  -*- lexical-binding: t; -*-

(nextel-page NotFoundPage
  :head (lambda (_route _data) (list :title "Not found"))
  :render (lambda (self)
            (jsx (p (:class "missing") "Nothing at " (plist-get (react-props self :route) :path)))))

;;; 404.el ends here
```

ルート表を書き出します（プロジェクトの中で）：

```text
$ vendor/elisp-next/bin/nextel-routes --check
nextel: not up to date: routes.el, index.html; write them (M-x nextel-write-routes, bin/nextel-routes)
$ vendor/elisp-next/bin/nextel-routes
nextel: 2 pages, 2 API routes: wrote routes.el, index.html
$ vendor/elisp-next/bin/nextel-routes --check
nextel: the routes are up to date
```

<a id="example-routes"></a>
書き出された `routes.el`：

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

書き出された index.html の領域：

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
`test/demo-test.el`。プロジェクトの隣に elisp-react と elisp-studio のチェックアウトを置いて実行します：

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

配信して API に問い合わせます（ネイティブの Emacs。Ctrl-C で止まります）：

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

ページそのものは、ブラウザで `http://127.0.0.1:8731/` を開いて見ます（初回は elisp-react と Emacs をそれぞれのサイトから取得します）：一覧、Add、タイトルが `Milk - Demo` で説明が `Item 1` の `#/item/1`、`No such item` と Retry が出る `#/item/9`、404 ページが出る `#/nowhere`。項目は `.data/items.eld` に入っています。
