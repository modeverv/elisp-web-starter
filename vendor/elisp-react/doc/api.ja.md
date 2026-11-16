# elisp-react API

> この文書は [doc/api.md](api.md) の日本語訳です（訳した時点の英語版：`ee6800c`）。英語版と食い違うときは英語版が、英語版とソースが食い違うときはソースが正しいものとします。

elisp-react の API の完全な説明です。React と Emacs Lisp を知っていて、elisp-react は初めて見る実装者（人でもコーディングエージェントでも）に向けて書いています。`main` にある `lisp/react.el`（プロトコル 3）、`lisp/react-testing.el`、`js/elisp-react.js` を説明します。この文書とソースが食い違うときは、ソースが正しいものとします。

以下の `elisp` ブロックはどれも、`react.el` と `react-testing.el` を読み込んだバッチの Emacs で、書かれたとおりに実行したものです。フォームの後のコメント `;; => VALUE` は、そのフォームが返した値を印字したものです。`;; error: SYMBOL` は、そのフォームがそのエラーを通知する（signal）ことを表します。`self` を定義せずに使っているブロックは、`(div () (input (:ref "field")))` を描画する、マウント済みのコンポーネントのインスタンスに `self` を束縛して実行しました。

全体を通して使う言葉:

- **ホスト**: `js/elisp-react.js`、つまりページの中の JavaScript です。Emacs を起動し、DOM 操作を適用し、イベントを転送します。
- **SELF**: コンポーネントのインスタンスです。`:render` や、その他のライフサイクル関数の引数です。
- **要素**: DOM を表す Lisp のデータです（[要素](#elements)を参照）。
- **リクエスト**: 後で答えが返ってくるもの（タイマー、fetch）をページに頼んだときに、Lisp が受け取る整数です。[`react-cancel`](#react-cancel) はこれを引数に取ります。
- **plist**: キーワードをキーとするプロパティリストです。`(:count 3 :label "x")`。

<a id="contents"></a>
## 目次

- [索引](#index)
- [全体像](#mental-model)
- [ページの設定](#page-setup)
- [要素](#elements)
- [コンポーネント](#components)
- [リファレンス](#reference)
- [非同期](#async)
- [テスト](#testing)
- [規則と落とし穴](#rules-and-pitfalls)
- [作例](#worked-examples)

<a id="index"></a>
## 索引

`react.el` と `react-testing.el` の公開シンボルのすべてです（名前に `--` を含まないもの）。構造体のアクセサは `cl-defstruct` が生成します。

| 名前 | 種類 | 用途 |
|---|---|---|
| [`jsx`](#jsx) | マクロ | バッククォートなしで、マークアップから要素を作ります。`react-jsx` の別名です。 |
| [`react-all`](#react-all) | 関数 | 複数の awaitable の値を、順に並べて返す awaitable。 |
| [`react-async`](#react-async) | マクロ | `react-await` で待てる本体を実行します。タスクを返します。 |
| [`react-async-error`](#react-async-error) | エラー | 操作が失敗した `react-await` で通知されます。 |
| [`react-await`](#react-await) | マクロ | `react-async` の中で、awaitable を待ち、その値を返します。 |
| [`react-cancel`](#react-cancel) | 関数 | リクエストを忘れ、ページにそれを止めるよう伝えます。 |
| [`react-changed-p`](#react-changed-p) | 関数 | 2つの plist が、指定したキーで異なるかどうか（`:should-update` 用）。 |
| [`react-clear-timer`](#react-clear-timer) | 関数 | `react-cancel` の別名（タイマー用）。 |
| [`react-component`](#react-define-component) | シンボルのプロパティ | `react-define-component` が定義を格納する場所。 |
| [`react-context`](#react-context) | 関数 | 上にある `react-provide` が渡す値を読みます。 |
| [`react-define-component`](#react-define-component) | 関数 | コンポーネントを定義します。 |
| [`react-dispatch-event`](#react-dispatch-event) | 関数 | ホストからの入口: DOM イベントのリスナーを実行し、flush します。 |
| [`react-effect`](#react-effect) | 関数 | 描画の中で使います: deps が変わったときに、描画の後で関数を実行します。 |
| [`react-event-source`](#react-event-source) | 関数 | Server-sent events（EventSource）。 |
| [`react-fetch`](#react-fetch) | 関数 | ブラウザの `fetch` をコールバックで使います。 |
| [`react-fetch-async`](#react-fetch-async) | 関数 | fetch の応答の awaitable。 |
| [`react-flush`](#react-flush) | 関数 | 保留中の描画を終わらせ、DOM 操作を返します。 |
| [`react-focus`](#react-focus) | 関数 | `:ref` を持つ要素にフォーカスします。 |
| [`react-force-update`](#react-force-update) | 関数 | `:should-update` を通さずに、1つのインスタンスを再描画します。 |
| [`react-form-value`](#react-form-value) | 関数 | 送信されたフォームの1つのフィールド。 |
| [`react-form-values`](#react-form-values) | 関数 | 送信されたフォームの、あるフィールドのすべての値。 |
| [`react-handler`](#react-handler) | 関数、構造体の型 | ページがその場で適用するオプション（preventDefault、キー...）を持つリスナーの prop。 |
| [`react-handler-function`](#react-handler) | 構造体のアクセサ | `react-handler` の関数。 |
| [`react-handler-options`](#react-handler) | 構造体のアクセサ | `react-handler` のオプションの plist。 |
| [`react-handler-p`](#react-handler) | 構造体の述語 | 値が `react-handler` かどうか。 |
| [`react-history-go`](#react-history-go) | 関数 | ブラウザの履歴の中を移動します。 |
| [`react-host-call`](#react-host-call) | 関数 | 後で答えが返るものを、ホスト（またはページのコマンド）に頼みます。 |
| [`react-host-replies`](#react-host-replies) | 関数 | ホストからの入口: 複数の答えをまとめて渡し、その後で1回 flush します。 |
| [`react-host-reply`](#react-host-reply) | 関数 | ホストからの入口: リクエストへの1つの答えを渡し、その後で flush します。 |
| [`react-host-tell`](#react-host-tell) | 関数 | ホスト（またはページのコマンド）に何かを伝えます。答えはありません。 |
| [`react-html`](#react-html) | 関数 | セレクタにマウントされているもの（HTML テキストとして）。 |
| [`react-html-tags`](#react-html-tags) | 定数 | `jsx` が認識する HTML タグ。 |
| [`react-inspect`](#react-inspect) | 関数 | マウントされているコンポーネントと、その props と state。 |
| [`react-intl`](#react-intl) | 関数 | ブラウザの `Intl` に、数値、日付、リストなどを書式化させます。 |
| [`react-intl-async`](#react-intl-async) | 関数 | `react-intl` の awaitable。 |
| [`react-invalidate`](#react-invalidate) | 関数 | クエリのキーに古いという印を付け、読み込み直します。 |
| [`react-invoke`](#react-invoke) | 関数 | DOM ノードのメソッド（focus、showModal、play...）を呼びます。 |
| [`react-jsx`](#jsx) | マクロ | `jsx` と同じです。 |
| [`react-listen-page`](#react-listen-page) | 関数 | `window` や `document` のイベントを受け取ります。 |
| [`react-locale`](#react-locale) | 関数 | 訪問者の言語とタイムゾーン。 |
| [`react-location`](#react-location) | 関数 | ページのアドレス。 |
| [`react-location-unwatch`](#react-location-unwatch) | 関数 | アドレスの監視を止めます。 |
| [`react-location-watch`](#react-location-watch) | 関数 | アドレスが変わったときに関数を呼びます。 |
| [`react-make-ref`](#react-make-ref) | 関数 | コンポーネントが下のコンポーネントに渡す ref。 |
| [`react-measure`](#react-measure) | 関数 | DOM ノードのボックスとスクロールを測ります。 |
| [`react-media-query`](#react-media-query) | 関数 | CSS のメディアクエリを追いかけます。 |
| [`react-mount`](#react-mount) | 関数 | 要素を、ページの要素の中に描画します。 |
| [`react-navigate`](#react-navigate) | 関数 | URL に移動します（履歴の push または replace）。 |
| [`react-node-id`](#react-node-id) | 関数 | ページが ref の DOM ノードを識別する番号。 |
| [`react-observe-visible`](#react-observe-visible) | 関数 | ノードが見えているかどうか（IntersectionObserver）。 |
| [`react-page-call`](#react-page-call) | 関数 | `window.elispReact.send` のための、ホストからの入口。 |
| [`react-plist-with`](#react-plist-with) | 関数 | キーを設定した plist のコピー。 |
| [`react-props`](#react-props) | 関数 | インスタンスの props。 |
| [`react-provide`](#react-provide) | 関数 | その下のすべてに値を渡す要素。 |
| [`react-provider`](#react-provider) | コンポーネント | `react-provide` の裏にある組み込みのコンポーネント。 |
| [`react-query`](#react-query) | 関数 | キーで読み込まれ、共有され、キャッシュされるデータ。 |
| [`react-query-data`](#react-query-data) | 関数 | 購読せずに、クエリのキーを読みます。 |
| [`react-query-set`](#react-query-set) | 関数 | クエリのキーにデータを入れます。 |
| [`react-race`](#react-race) | 関数 | 複数のうち最初の答えの awaitable。 |
| [`react-ref`](#react-ref) | 関数 | `:ref` を持つ、マウントされた要素。 |
| [`react-refresh`](#react-refresh) | 関数 | すべてのインスタンス（ある型のもの）を再描画します。 |
| [`react-render-error`](#react-render-error) | エラー | `:render` が失敗し、どのエラー境界も捕まえなかった。 |
| [`react-render-to-string`](#react-render-to-string) | 関数 | ページなしで（サーバー側で）、要素を HTML テキストにします。 |
| [`react-reset`](#react-reset) | 関数 | マウントされたものをすべて忘れます（テスト用）。 |
| [`react-response-bytes`](#react-response-bytes) | 関数 | base64 の応答の本文を、unibyte の文字列にします。 |
| [`react-response-header`](#react-response-header) | 関数 | 応答のヘッダーの1つ。 |
| [`react-response-json`](#react-response-json) | 関数 | 応答の本文を JSON として解析したもの。 |
| [`react-root`](#react-root) | 関数 | セレクタにマウントされている、コンポーネントのインスタンス。 |
| [`react-set-interval`](#react-set-interval) | 関数 | N ミリ秒ごとに関数を呼びます。 |
| [`react-set-meta`](#react-set-meta) | 関数 | `<meta>` を設定または削除します。 |
| [`react-set-property`](#react-set-property) | 関数 | ノードの DOM プロパティを設定します。 |
| [`react-set-state`](#react-set-state) | 関数 | state を変え、描画を予定します。 |
| [`react-set-timeout`](#react-set-timeout) | 関数 | N ミリ秒後に関数を1回呼びます。 |
| [`react-set-title`](#react-set-title) | 関数 | 文書のタイトルを設定します。 |
| [`react-shallow-equal`](#react-shallow-equal) | 関数 | 2つの plist が同じ値を持つかどうか（1段だけ）。 |
| [`react-sleep`](#react-sleep) | 関数 | N ミリ秒後に終わる awaitable。 |
| [`react-state`](#react-state) | 関数 | インスタンスの state。 |
| [`react-storage-get`](#react-storage-get) | 関数 | ページの localStorage から値を読みます。 |
| [`react-storage-remove`](#react-storage-remove) | 関数 | localStorage からキーを削除します。 |
| [`react-storage-set`](#react-storage-set) | 関数 | Lisp の値を localStorage に保存します。 |
| [`react-storage-unwatch`](#react-storage-unwatch) | 関数 | ストレージの監視を止めます。 |
| [`react-storage-watch`](#react-storage-watch) | 関数 | 別のタブがキーを変えたときに、それを知ります。 |
| [`react-svg-tags`](#react-svg-tags) | 定数 | `jsx` が認識する SVG タグ。 |
| [`react-task`](#react-task) | 構造体の型 | `react-async` が返すもの。 |
| [`react-task-cancel`](#react-task-cancel) | 関数 | タスクを止めます。 |
| [`react-task-iterator`](#react-task) | 構造体のアクセサ | タスクのジェネレーター（内部用）。 |
| [`react-task-p`](#react-task) | 構造体の述語 | 値がタスクかどうか。 |
| [`react-task-request`](#react-task) | 構造体のアクセサ | タスクが待っているリクエスト。なければ nil。 |
| [`react-task-state`](#react-task) | 構造体のアクセサ | nil（実行中）、`done`、`failed`、`cancelled` のいずれか。 |
| [`react-task-value`](#react-task) | 構造体のアクセサ | 本体の値、または失敗のメッセージ。 |
| [`react-task-waiting`](#react-task) | 構造体のアクセサ | そのタスクを await しているもの（内部用）。 |
| [`react-testing-answer`](#react-testing-answer) | 関数 | テストキット: コマンドの最も古いリクエストに答えます。 |
| [`react-testing-answer-fetch`](#react-testing-answer-fetch) | 関数 | テストキット: 最も古い fetch に答えます。 |
| [`react-testing-attribute`](#react-testing-attribute) | 関数 | テストキット: ノードの属性。 |
| [`react-testing-click`](#react-testing-click) | 関数 | テストキット: ノードをクリックします。 |
| [`react-testing-dispatch`](#react-testing-dispatch) | 関数 | テストキット: 任意のイベントを、バブリングさせて発行します。 |
| [`react-testing-find`](#react-testing-find) | 関数 | テストキット: 最初に一致する要素。 |
| [`react-testing-find-all`](#react-testing-find-all) | 関数 | テストキット: 一致するすべての要素。 |
| [`react-testing-flush`](#react-testing-flush) | 関数 | テストキット: 保留中の操作を、偽のページに適用します。 |
| [`react-testing-html`](#react-testing-html) | 関数 | テストキット: 偽のページを HTML にしたもの。 |
| [`react-testing-input`](#react-testing-input) | 関数 | テストキット: 入力欄に入力します。 |
| [`react-testing-invoked`](#react-testing-invoked) | 変数 | テストキット: ノードに対して呼ばれたメソッド。 |
| [`react-testing-key`](#react-testing-key) | 関数 | テストキット: キーを押します。 |
| [`react-testing-load`](#react-testing-load) | 関数 | テストキット: 最初からやり直し、ファイルを読み込みます。 |
| [`react-testing-location`](#react-testing-location) | 関数 | テストキット: ページのアドレスを変えます。 |
| [`react-testing-property`](#react-testing-property) | 関数 | テストキット: Lisp が設定した DOM プロパティ。 |
| [`react-testing-render`](#react-testing-render) | 関数 | テストキット: 最初からやり直し、要素を描画します。 |
| [`react-testing-requests`](#react-testing-requests) | 変数 | テストキット: 答えを待っているリクエスト。 |
| [`react-testing-reset`](#react-testing-reset) | 関数 | テストキット: すべてを忘れます。 |
| [`react-testing-storage`](#react-testing-storage) | 関数 | テストキット: ページのストレージに値を入れます。 |
| [`react-testing-submit`](#react-testing-submit) | 関数 | テストキット: フォームを、そのフィールドとともに送信します。 |
| [`react-testing-text`](#react-testing-text) | 関数 | テストキット: ノードのテキスト。 |
| [`react-testing-time-passes`](#react-testing-time-passes) | 関数 | テストキット: 待っているタイマーを発火させます。 |
| [`react-testing-told`](#react-testing-told) | 変数 | テストキット: Lisp がページに送った通知。 |
| [`react-unmount`](#react-unmount) | 関数 | セレクタにマウントされているものをアンマウントします。 |
| [`react-url-query`](#react-url-query) | 関数 | クエリ文字列を alist にしたもの。 |
| [`react-websocket`](#react-websocket) | 関数 | WebSocket を開きます。 |
| [`react-websocket-send`](#react-websocket-send) | 関数 | WebSocket でテキストを送ります。 |

ホストの JavaScript API（`start()`、`window.elispReact`、`window.elispReactCommands`、document のイベント）は[ページの設定](#page-setup)にあります。

<a id="mental-model"></a>
## 全体像

<a id="what-runs-where"></a>
### 何がどこで動くか

- **ホスト**は、ページのメインスレッドで動きます。DOM 操作を適用し、DOM イベントを待ち受け、Lisp がリクエストの中ではできないこと（タイマー、`fetch`、`localStorage`、WebSocket、履歴、`Intl`）を行います。
- **Emacs 30.2** は、worker の中で WebAssembly として動きます（wasmacs の eval service）。`react.el` とページの Lisp はそこで動きます。Lisp が動くのは、ホストが呼んだときだけです。つまり、起動時、DOM イベントのとき、リクエストへの答えのとき、新しいアドレスのとき、別のタブが保存した値のとき、`window.elispReact.send` のときです。それぞれの呼び出しは最後まで実行され、描画し、操作のベクタを返します。サービスは呼び出しに1つずつ、順に答えます。
- Lisp は DOM に決して触れません。DOM ノードは、Lisp 自身が決めた番号で知っています。Lisp がページに求めること（フィールドにフォーカスする、タイマーを始める、URL を fetch する）も、同じベクタの中の操作です。答えは後で、新しい呼び出しとして返ってきます。
- 値は JSON として受け渡されます。JSON から Lisp へ: オブジェクトはキーワードをキーとする plist、配列はベクタ、`true` は `t`、`false` と `null` は `nil` になります。Lisp から JSON へ: キーワードをキーとする plist はオブジェクト、ベクタは配列、`t` は `true`、`:false` は `false`、`nil` は `null` になります。シンボルや、plist でないリスト（文字列のリスト）には JSON の形がありません。そのときは答え全体が失敗します。

<a id="page-lifecycle"></a>
### ページのライフサイクル

1. モジュール `elisp-react.js` は、文書の解析が終わった後で実行されます。文書に `<script type="text/emacs-lisp">` が1つ以上あり、`<html>` に `data-elisp-react-manual` 属性がなければ、`start()` を呼び、`window.elispReact = { ready }` を設定します。
2. ホストは wasmacs のサイトから wasmacs のクライアントを import し、Emacs を起動します。それと並行して、すべての Lisp スクリプトのテキスト（`src` を `cache: "no-store"` で取得したもの、またはインラインのテキスト）、`react.el`、そして指定されていればコンパイル済みコードのマニフェストを fetch します。
3. `react.el` を読み込み、`react--protocol` を自分の番号（3）と照らし合わせます。一致しなければ起動を止めます。
4. ファイル名が `^[\w.+-]+\.el$` に一致するページのスクリプトをすべて `/tmp/elisp-react/lib/` に書き出し、そのディレクトリを `load-path` に加えます。
5. ページに保存された値（`localStorage`）、ページのアドレス、訪問者のロケールを Lisp に渡します。
6. ページのスクリプトを、文書の順に1つずつ読み込みます。それぞれ Emacs の中でバイトコンパイルされ（またはキャッシュかマニフェストから取り出され）、読み込まれます。コンパイルできないファイル（警告ではなくエラーが出るもの）は、代わりにソースから評価されます。こうすると、表示されるエラーがプログラム自身のエラーになります。
7. `react-flush` を呼び、操作を適用します。ここで最初の画面が現れます。その後 `ready` を解決し、`document` で `elisp-react:ready` を発火します。

スクリプトの中の `react-mount` は、その場で描画します（手順 6）。DOM 操作は手順 7 まで待ちます。`:did-mount` 関数とエフェクトも、そこで実行されます。

**コンパイル済みコードのキャッシュ。** 各ファイルのバイトコードは、`localStorage` の `elisp-react:compiled:URL` に保存されます（`cache: "session"` なら `sessionStorage`）。次からは、Emacs のバージョン、その前に読み込まれたファイルのハッシュ、そのファイルのソースから求めた SHA-256 ハッシュで見つけ直します。バイトコードには、使ったマクロの展開結果が入っています。そのため、`react.el` やどれかのファイルが変わると、そのファイルとそれより後のすべてのファイルがコンパイルし直されます。`crypto.subtle` がない場所（localhost 以外のホストから素の HTTP で配信されるページ）では何も保存されず、起動のたびにコンパイルします。`elisp-react:compiled-by:PAGE` には、各ページが読み込んだファイルが記録されます。どのページももう読み込まないコードは削除されます。

**前もってコンパイルする。** `node tools/compile.mjs -o compiled.json app.el ...`（ページのファイルを、ページでの順に並べます。リポジトリの隣に wasmacs のチェックアウトがあるか、`$WASMACS` が必要です）は、同じハッシュでバイトコードのマニフェストを書き出します。`<meta name="elisp-react:compiled" content="compiled.json">` でそれを指定します。ハッシュがマニフェストにあるファイルは、ページの中ではコンパイルされません。

<a id="render-cycle"></a>
### 描画のサイクル

- `react-mount` は同期的に描画します。ツリー全体の `:initial-state` と `:render` が、その呼び出しの中で実行されます。DOM 操作はキューに入れられます。
- `react-set-state` は決して描画しません。新しい state の plist をすぐに設定し（`react-state` はすぐに新しい値を返します）、インスタンスに dirty の印を付けます。描画は、ホストからの現在の呼び出しを締めくくる flush（`react-flush`）で行われます。1つのハンドラの中で何度 `react-set-state` を呼んでも、描画は1回です。
- flush は、残りがなくなるまで繰り返します。dirty なインスタンスを親から先に描画し、次に `:did-mount` 関数、次に `:did-update` 関数、次にエフェクトを実行します。そのどれかで設定された state は、同じ flush の次の回で描画されます。100回繰り返すと、エラー `"Components keep changing state while rendering"` を出してあきらめます。
- コンポーネントは、親が描画されるたびに再描画されます。ただし、その `:should-update` が nil を返したとき（または `:pure` が何も変わっていないと判断したとき）は除きます。飛ばされたコンポーネントは、その下のすべてを飛ばします。ただし、変わったコンテキストやクエリを読んでいるものは例外で、強制的に描画されます。
- 差分計算: 新しい要素は、種類（テキスト、要素、コンポーネント、フラグメント）、タグまたはコンポーネント名、`:key` が同じなら、マウント済みのものを引き継ぎます。そのときはその場で更新され、コンポーネントは state を保ちます。そうでなければ、古いものがアンマウントされ、新しいものがマウントされます。子は `:key` で対応付けられます（`equal` で比較）。key のない子は、key のない子どうしの中での位置で対応付けられます。

<a id="lifecycle-order"></a>
### ライフサイクルの順序

```elisp
(defvar order-log nil)
(react-define-component 'Child
  :initial-state (lambda (props) (push (list 'child-initial (plist-get props :n)) order-log) nil)
  :did-mount (lambda (self) (push (list 'child-did-mount (react-props self :n)) order-log))
  :did-update (lambda (self _props _state) (push (list 'child-did-update (react-props self :n)) order-log))
  :will-unmount (lambda (self) (push (list 'child-will-unmount (react-props self :n)) order-log))
  :render (lambda (self)
            (push (list 'child-render (react-props self :n)) order-log)
            (react-effect self 'effect (react-props self :n)
              (lambda () (push 'child-effect order-log) (lambda () (push 'child-cleanup order-log))))
            (jsx (li (react-props self :n)))))
(react-define-component 'Parent
  :initial-state (lambda (_props) (push 'parent-initial order-log) (list :n 1))
  :did-mount (lambda (_self) (push 'parent-did-mount order-log))
  :did-update (lambda (_self _props _state) (push 'parent-did-update order-log))
  :will-unmount (lambda (_self) (push 'parent-will-unmount order-log))
  :render (lambda (self)
            (push 'parent-render order-log)
            (jsx (ul (Child (:n (react-state self :n)))))))

(react-mount (jsx (Parent)) "#app")
(reverse order-log)
;; => (parent-initial parent-render (child-initial 1) (child-render 1))
(setq order-log nil)
(react-flush)
(reverse order-log)
;; => ((child-did-mount 1) parent-did-mount child-effect)
(setq order-log nil)
(react-set-state (react-root "#app") :n 2)
(reverse order-log)
;; => nil
(react-flush)
(reverse order-log)
;; => (parent-render (child-render 2) parent-did-update (child-did-update 2) child-cleanup child-effect)
(setq order-log nil)
(react-unmount "#app")
(reverse order-log)
;; => (parent-will-unmount (child-will-unmount 2) child-cleanup)
```

- マウント: `react-mount` の中で、`:initial-state`、次に `:render` が、親から子の順に実行されます。flush では、`:did-mount` が子から親の順に実行されます。
- 更新: `:render` は親から子の順です。`:did-update` も親から子の順です（React は子を先に実行します）。その後にエフェクトが、`react-effect` が呼ばれた順に、それぞれ前回の実行のクリーンアップの後で実行されます。
- アンマウント: `:will-unmount` は親から子の順です。インスタンスのエフェクトのクリーンアップは、そのインスタンス自身の `:will-unmount` の直後に実行されます。

<a id="page-setup"></a>
## ページの設定

<a id="html"></a>
### HTML

```html
<!doctype html>
<html lang="en">
  <head>
    <meta charset="utf-8">
    <title>App</title>
  </head>
  <body>
    <div id="app">Loading Emacs…</div>
    <script type="text/emacs-lisp" src="helpers.el"></script>
    <script type="text/emacs-lisp" src="app.el"></script>
    <script type="module" src="https://modeverv.github.io/elisp-react/js/elisp-react.js"></script>
  </body>
</html>
```

- `<script type="text/emacs-lisp">` は、`src` を持っても、インラインのテキストを持ってもかまいません。数はいくつでもよく、`react.el` の後に、文書の順に読み込まれます。
- モジュールのスクリプトは、どこに置いてもかまいません。`react.el` は `elisp-react.js` の隣にある `../lisp/react.el` から取得されるので（`library` オプションで変えられます）、2つは同じ場所から来ます。
- 最初の行に `lexical-binding:` を含まないファイルには、ページの中で `;;; -*- lexical-binding: t; -*-` が先頭に付け加えられます。
- **load-path。** URL が `^[\w.+-]+\.el$` に一致するファイル名で終わるスクリプトはすべて、最初のページのファイルを読み込む前に、その名前で `load-path` に置かれます。`(require 'helper)` は、ページのどこに並んでいても `helper.el` を見つけます。インラインのスクリプトは `load-path` に置かれません。自分の番より前に require されたファイルは、2回読み込まれます。1回目は `require` によって（コンパイルされずにソースから）、2回目は自分の番にコンパイルされて読み込まれます。ライブラリは、それを require するファイルより前に並べ、各ライブラリの最後に `(provide 'NAME)` を書いてください。
- Emacs 自身のライブラリは `require` で読み込みます（`seq`、`subr-x`、`cl-lib`、`json`、`url`...）。そのファイルは、Emacs が読むときに eval service が取得します。`cl-lib` と `generator` は `react.el` が読み込みます。他人の Lisp は、スクリプトとして並べます。`package.el` はダウンロードできません。
- `react.el` は `(provide 'react)` で終わります。そのため、アプリケーションのファイルの先頭に書いた `(require 'react)` は、ページの中では何もせず、ネイティブの Emacs ではそのファイルを読み込み、コンパイルできるようにします。

<a id="settings"></a>
### 設定

自動で起動するページは、`<meta name="elisp-react:...">` を読みます。手で起動するページは、オプションを `start()` に渡します。

| `<meta name>` | `start()` のオプション | 値 | 既定値 |
|---|---|---|---|
| `elisp-react:wasmacs` | `wasmacs` | wasmacs のサイトの URL。ページのアドレスの `?wasmacs=URL` は meta を上書きします（オプションは上書きしません）。これは `localhost`、`127.0.0.1`、`[::1]` でだけ働きます。 | `https://modeverv.github.io/wasmacs/` |
| `elisp-react:timeout` | `timeout` | Lisp が1回の呼び出しに答えるのにかけてよいミリ秒。`0` は無制限。それを過ぎると、ホストは Emacs を止め、エラーシンボル `timeout` を報告します。ページはリロードしなければなりません。 | `30000` |
| `elisp-react:boot-timeout` | `bootTimeout` | 起動にかけてよいミリ秒。`0` は無制限。それを過ぎると、起動は `boot-timeout` で失敗します。 | `120000` |
| `elisp-react:compiled` | `compiled` | `tools/compile.mjs` が作ったマニフェストの URL。 | なし |
| `elisp-react:cache` | `cache` | コンパイル済みコードを保存する場所。meta: `local`、`session`、`none`（それ以外の値は `local`）。オプション: `true` または `"local"`、`"session"`、`false`。 | `local` |
| `elisp-react:storage` | `storage` | `react-storage-set` が値を保存するときの名前。キーは `elisp-react:NAME:KEY` になります。 | ページのパスから末尾の `index.html` を除いたもの（`/app/` と `/app/index.html` では `/app/`。`/app/other.html` というページでは、そのまま） |
| | `location` | `"browser"`: ページのアドレス。`"memory"`: ホストが保持するアドレス。`/` から始まり、独自の履歴を持ちます。ハッシュリンクはホスト自身がたどります。 | `"browser"`。`about:srcdoc` のフレームの中では `"memory"` |
| | `library` | `react.el` の URL。 | `elisp-react.js` の隣にある `../lisp/react.el` |
| | `sources` | ページのスクリプトの代わりに読み込む `[{ name, text }]`。 | ページのスクリプト |
| | `fetch` | `react-fetch` で `fetch` の代わりに使う関数。 | `fetch` |
| | `signal` | 起動を中止する `AbortSignal`（エラーシンボル `aborted`）。 | なし |
| | `onProgress` | `({ phase, url, bytes, from }) => void`。phase は `"build id"`、`"download"`、`"emacs"`、その後ファイルごとに `"lisp"`（`from`: `"manifest"`、`"kept"`、`"compiled"`、`"evaluated"`）。 | なし |

`timeout` や `boot-timeout` の meta が 0 以上の数でなければ、ないものとして扱われます。

<a id="starting-by-hand"></a>
### 手で起動する

```html
<html lang="en" data-elisp-react-manual>
  <body>
    <div id="app">Loading Emacs…</div>
    <script type="text/emacs-lisp" src="app.el"></script>
    <script type="module">
      import { start } from "https://modeverv.github.io/elisp-react/js/elisp-react.js";
      window.elispReact = { ready: start({ timeout: 10000 }) };
      window.elispReact.ready.then((app) => Object.assign(window.elispReact, app), console.error);
    </script>
  </body>
</html>
```

`start(options)` は、下のオブジェクトの promise を返します。手で起動したときは、何も `elisp-react:ready` を発火せず、何も `window.elispReact` にコピーされず、起動の失敗もページに表示されません。この3つは呼び出し側が扱います。

| プロパティ | |
|---|---|
| `emacs` | eval service: `emacs.eval(source)`、`emacs.call(name, ...args)`、`emacs.terminate()`。 |
| `version`, `bootMs`, `cached`, `files` | Emacs のバージョン。起動にかかった時間。何もダウンロードしなかったかどうか。`"on demand"` または `"all"`。 |
| `load(name, text)` | 変更したソースを、動いているページの中でコンパイルして読み込み、その後 flush します。`{ file, log, from }` で解決します。ソースは読み込めたが描画が失敗したときは、それに `renderError` が加わります。描画がうまくいくと、エラーの枠は消えます。`load` のコンパイル済みコードは決して保存されません。 |
| `send(name, ...args)` | Lisp の関数 `name` を `args`（JSON）で呼び、それが変えたものを描画します。ページが更新されると（値なしで）解決します。Lisp のエラーの後や、Emacs が止められていたときは reject します。 |
| `run(text)` | フォームをそのまま（コンパイルせずに）評価し、その後 flush します。 |
| `location` | `{ current, navigate(url, replace), go(delta) }`: アドレス。ページの周りのツールのためのものです。 |
| `library`, `compileLogs` | `react.el` の `{ file, log, from }`。ページのファイルの `[{ name, file, log, from }]`。`log` はバイトコンパイラが出力したものです（何もなければ ""）。 |
| `dom` | ホストの DOM 適用器（内部用）。 |

自動で起動するページには、最初から `window.elispReact = { ready }` があります。起動に成功すると、上のプロパティが `window.elispReact` にコピーされます。

<a id="document-events"></a>
### document のイベント

| `document` のイベント | `detail` |
|---|---|
| `elisp-react:ready` | 上のオブジェクト（自動で起動したときだけ）。 |
| `elisp-react:error` | `Error`。わかっていれば、`symbol` は Lisp のエラーシンボル、`timeout`、`boot-timeout`、`aborted` のいずれかです。 |
| `elisp-react:progress` | `{ phase, url, bytes, from }`。 |
| `elisp-react:location` | アドレスが変わった後の `{ href, pathname, search, hash }`。 |

<a id="errors-on-the-page"></a>
### ページ上のエラー

- 呼び出し（イベントハンドラ、答え、描画）の中で Lisp のエラーが起きると、その呼び出しは reject されます。ホストはそれをログに出し、`elisp-react:error` を発火し、ページの下端に固定された赤い `<pre id="elisp-react-error">` に `SYMBOL: MESSAGE` を追加します。その呼び出しの DOM 操作は1つも適用されません。Lisp の中ですでに設定された state はそのまま残り、待っていたものは次の flush で描画されます。
- ホストが拒否する DOM 操作は、ベクタを適用している最中に例外を投げます。許可リストにない `react-invoke` のメソッド、`react-host-call` や `react-host-tell` の未知のコマンド、何にも一致しない `react-mount` のセレクタがそれにあたります。そのベクタの中でそれより後の操作は適用されず、それ以後、Lisp が考えるページと実際のページが食い違います。
- 安全でない属性（`on` で始まる名前、`srcdoc`、`href`、`src`、`action`、`formaction` などの URL 属性の中の `javascript:` や `vbscript:` の URL）は、コンソールに警告を出して取り除かれます。ベクタの残りは適用されます。
- タイムアウトより長くかかった呼び出しは、Emacs を止めます。ページはそのままの状態で残り、`timeout` を報告します。
- ページのファイルを読み込む間のエラー（そのトップレベルのエラー、またはその `react-mount` の最初の描画でのエラー）は、起動を止めます。`ready` は reject され、自動で起動したページは、ファイルの URL を前に付けてエラーを表示します。

`elisp-react.js` 自体が読み込めなければ、何も動かず、何も表示されません。ページは、少し待ってから `window.elispReact` を確かめる普通のスクリプトで、これに備えられます。

<a id="versions-and-the-protocol"></a>
### バージョンとプロトコル

- `https://modeverv.github.io/elisp-react/js/elisp-react.js` は `main` に従います。リリースのタグ `vX.Y.Z` はそれぞれ、`https://modeverv.github.io/elisp-react/v/X.Y.Z/js/elisp-react.js` に、それ自身の `react.el` を隣に置いて保存されます。`v0.1.0` はプロトコル 2 を話します。フラグメント（`<>`）も `react-inspect` もありません。
- `react.el` を読み込んだ後、ホストは `react--protocol` を自分の番号と比べ、一致しなければ拒否します: `... speaks protocol N, this elisp-react.js 3: load the two from one release`。
- Emacs 本体は wasmacs のサイトから来ます。こちらも変わっていきます。固定したいページは、自分でコピーを配信し、`elisp-react:wasmacs` でそれを指定します。

<a id="elements"></a>
## 要素

<a id="plain-list-form"></a>
### 素のリスト形式

要素は Lisp のデータです。

| 形 | 描画されるもの |
|---|---|
| `"text"`, `42`, `1.5` | テキストノード。数は `(format "%s" N)` で書き出されます。 |
| `(TAG PROPS CHILD...)` | DOM 要素。`TAG` はシンボルで、その名前が、書いたとおりに DOM のタグになります（`div`、`input`、`svg`、`x-widget`）。 |
| `(TAG CHILD...)` | props のない同じもの。 |
| `(NAME PROPS CHILD...)` | `NAME` が `react-define-component` で定義されていれば（そのシンボルがプロパティ `react-component` を持っていれば）、コンポーネント。そうでなければ、`NAME` は DOM のタグです。 |
| `(<> CHILD...)`, `(<> (:key K) CHILD...)` | フラグメント。その子を、囲む要素なしで置きます。 |

要素の2番目の項目は、それが `nil` か、最初の項目がキーワードであるリストのとき、props になります。そのため `(p "x")`、`(p () "x")`、`(p nil "x")` は同じです。

props の後の子:

- `nil` と `t` は飛ばされます。
- 最初の項目がシンボルでないリスト（`mapcar` が返すもの。`nil` で始まる場合も含みます）は、再帰的に展開して埋め込まれます。
- 文字列や数はテキストです。シンボルで始まるリストは要素です。
- それ以外のもの（シンボル、ベクタ、キーワード）は `(error "Not an element: X")` を通知します。シンボルは `symbol-name` か `format` でテキストに、ベクタ（JSON の配列）は `(append VECTOR nil)` か `mapcar` でリストに変えてください。

```elisp
(react-mount `(ul () (li () "a") nil ,(mapcar (lambda (n) `(li () ,n)) '(1 2)) t) "#app")
(react-html "#app")
;; => "<ul><li>a</li><li>1</li><li>2</li></ul>"
(react-mount '(p () loading) "#other")
;; error: error
```

バッククォートでは、計算する部分のすべてにカンマが必要です。ハンドラも同じです: `(button (:on-click ,(lambda (_event) ...)))`。カンマがないと、その prop はクォートされたリストになり、`self` を捕捉するクロージャになりません。`jsx` マクロにはカンマは要りません。

大文字で始まるのにコンポーネントでないタグ（つづりを間違えた名前や、ファイルが後で読み込まれるコンポーネント）は、未知の要素として描画され、メッセージを1回だけ表示します: `react: VideoCrad is not a defined component; ...`。カスタム要素は、ハイフンを含む名前です: `(x-widget (:size "2"))`、`jsx` の中では `(X-widget ...)`。

<a id="jsx"></a>
#### jsx

`(jsx FORM)` と `(react-jsx FORM)` は同じ1つのマクロです。マークアップを、素のリスト形式を組み立てる `list` の呼び出しに展開します。展開の時点では何も調べません。

1. FORM はマークアップでなければなりません。つまり、最初の項目が `<>`、[`react-html-tags`](#react-html-tags) か [`react-svg-tags`](#react-svg-tags) に含まれるもの、または名前が `A`–`Z` で始まるシンボルであるリストです。そうでなければ、展開は `jsx: FORM does not start with an HTML tag, a Capitalized component name or <>` を通知します。
2. マークアップ `(TAG X ...)` では、`()`/`nil` か、最初の項目がキーワードであるリストのとき、`X` が props です。props は、キーワードをキーとする `KEY VALUE` の組として書き出さなければなりません。そうでなければ、展開は `jsx: X is not a prop name in FORM` を通知します。`jsx` では props を変数で渡せません。そのような要素は `list` で組み立ててください: `(list 'button (append '(:class "primary") extra-props) "OK")`。
3. prop の値と子は、どれも同じ規則で読まれます。マークアップは要素になり、それ以外は Lisp として評価されます（文字列、数、変数、`(format ...)`、`(when ...)`、`(mapcar ...)`）。その値は、要素、要素のリスト、テキスト、nil のどれでもかまいません。
4. そうした Lisp の中のマークアップには、もう一度 `jsx` が要ります: `(when done (jsx (b "!")))`、`(mapcar (lambda (item) (jsx (li item))) items)`。
5. 大文字で始まる名前だけがコンポーネントです。`(jsx (div (counter)))` は関数 `counter` を呼びます。タグ名で始まるリストは常にマークアップです。Emacs の関数 `mark` や、`label`、`filter`、`search`、`time`、`title`、`data`、`text` という名前の自作の関数は、`jsx` の中では直接呼べません。

```elisp
(macroexpand '(jsx (p (:id name) (upcase name))))
;; => (list 'p (list :id name) (upcase name))
(let ((count 3) (items '("x" "y")))
  (jsx (div (:class "box")
         (p (format "Count: %d" count))
         (when (> count 5) (jsx (strong "many")))
         (mapcar (lambda (item) (jsx (li (:key item) item))) items))))
;; => (div (:class "box") (p nil "Count: 3") nil ((li (:key "x") "x") (li (:key "y") "y")))
(macroexpand '(jsx (counter (:start 3))))
;; error: error
```

`react.el` を読み込むと、すべてのタグと `react-define-component` は、最初の引数（props）を特別な引数（distinguished argument）としてインデントされます。

<a id="fragments"></a>
#### フラグメント

`(<> CHILD...)` は、自分の子を、自分が置かれた位置、つまり親の子どうしの間に置きます。フラグメントは `:key` 以外の props を取りません。それ以外の props は `A fragment takes no props but :key: ...` を通知します。要素のリストを返す `:render` は、それらのフラグメントを返したことになります。ページの上では、フラグメントはその子のノードと、それに続く、位置を示す空のテキストノードです。

```elisp
(react-define-component 'Row        ; a row that opens a second row below it
  :initial-state (lambda (_props) (list :open nil))
  :render
  (lambda (self)
    (jsx (<> (tr (:on-click (lambda (_event) (react-set-state self :open (not (react-state self :open)))))
               (td (react-props self :name)))
             (when (react-state self :open)
               (jsx (tr (:class "detail") (td "more"))))))))
(react-testing-render (jsx (table (tbody (Row (:name "a")) (Row (:name "b"))))))
(react-testing-click (react-testing-find :tag 'tr :text "a"))
(react-testing-html)
;; => "<table><tbody><tr><td>a</td></tr><tr class=\"detail\"><td>more</td></tr><tr><td>b</td></tr></tbody></table>"
```

<a id="props-of-dom-elements"></a>
### DOM 要素の props

| prop | 効果 |
|---|---|
| `:key` | 描画されません。兄弟の中でその子を識別します（`equal` で比較）。 |
| `:ref` | 描画されません。その要素を描画したコンポーネントが、その DOM ノードを見つけるための名前（任意のデータで、`equal` で比較。普通は文字列）。または [`react-make-ref`](#react-make-ref) の ref。 |
| `:on-EVENT` | DOM イベント `EVENT` のリスナー。イベント名は `:on-` の後のテキストそのままです（`:on-click`、`:on-input`、`:on-change`、`:on-submit`、`:on-keydown`、`:on-dblclick`、`:on-pointerdown`、`:on-close`）。値は、引数1つ（イベントの plist）の関数、[`react-handler`](#react-handler)、または `nil`（リスナーなし）です。 |
| `:value` | DOM プロパティ `value`。文字列でなければ `format` で書き出し、`nil` なら `""`。要素が描画されるたびに書き込まれます。 |
| `:checked` | DOM プロパティ `checked`。値が `nil` か `:false` でなければ true。描画のたびに書き込まれます。 |
| `:class` | 文字列、またはリスト。リストなら、`nil` の項目は捨てられ、残りが空白でつながれます。 |
| `:style` | 文字列、または plist。`(:color "red" :margin-top 4)` は `"color: red; margin-top: 4px"` になります。数には `px` が付きます。ただし `0`、カスタムプロパティ（`:--gap`）、単位のないプロパティ（`opacity`、`z-index`、`flex`、`flex-grow`、`flex-shrink`、`order`、`font-weight`、`line-height`、`zoom`、`column-count`、`orphans`、`widows`、`tab-size`、`fill-opacity`、`stroke-opacity`、`stroke-miterlimit`、`flood-opacity`、`stop-opacity`、`animation-iteration-count`、`grid-row`、`grid-column`、`grid-row-start`、`grid-row-end`、`grid-column-start`、`grid-column-end`、`aspect-ratio`、`scale`）は除きます。`nil` の値は省かれます。CSSOM を通して設定するので、style に `'unsafe-inline'` を許さない CSP でも使えます。 |
| `:inner-html` | よそから来た HTML テキスト。ホストはそれを表示する前に掃除します。その要素は子を持ってはなりません（`A <div> with :inner-html has children too`）。 |
| `:aria-NAME` | `t` は `"true"`、`:false` は `"false"`、`nil` は属性を取り除きます。 |
| それ以外 | キーワードの名前を、書いたとおりに名前とした属性（`:for`、`:tabindex`、`:data-id`、`:viewBox`、`:stroke-width`）。文字列はそのまま使い、数やシンボルは format します。`t` は値を空にして設定し（属性があるだけの状態）、`nil` と `:false` は取り除きます。 |

```elisp
(react-render-to-string
 '(div (:class ("card" nil active) :hidden t :title nil :data-n 3 :aria-pressed :false
        :style (:width 120 :opacity 0.5 :margin 0 :--gap 4))
    (input (:value 42 :disabled nil))))
;; => "<div class=\"card active\" hidden data-n=\"3\" aria-pressed=\"false\" style=\"width: 120px; opacity: 0.5; margin: 0; --gap: 4\"><input value=\"42\"></div>"
```

**制御された入力。** `:value`（または `:checked`）と、state を設定するリスナーを持つ入力は、制御された入力です。ホストは、ノードのより新しい `input` や `change` イベントがまだ Lisp を待っている間は、そのノードの `value` を書き込みません。そのため、速く入力しても入力は失われません。`<select>` は、その option ができた後で `:value` を受け取ります。

**ホストの属性ポリシー。** ホストは、`on` で始まる属性名（大文字小文字を問いません）と `srcdoc`、そして `href`、`src`、`action`、`formaction`、`data`、`xlink:href`、`background`、`cite`、`codebase`、`longdesc`、`manifest`、`profile`、`usemap` の中の `javascript:`/`vbscript:` の URL（および SVG アニメーションの値の中のスクリプトの URL）を捨てます。その属性を取り除き、コンソールに警告を出します。

**`:inner-html` の掃除。** HTML は、不活性な `<template>` の中で解析されます。`script`、`style`、フレーム、`object`、`embed`、`template`、`noscript`、`link`、`meta`、`base`、フォームのコントロール、`svg`、`math`、メディア、`canvas`、`dialog`、`slot` は、その中身ごと捨てられます。`a abbr b bdi bdo blockquote br caption cite code col colgroup dd del details dfn div dl dt em figcaption figure h1`–`h6 hr i img ins kbd li mark ol p picture pre q rp rt ruby s samp small source span strong sub summary sup table tbody td tfoot th thead time tr u ul var wbr` に含まれない要素は、その子に置き換えられます。`href src srcset sizes alt title class width height colspan rowspan lang dir start reversed type datetime cite open loading headers scope` 以外の属性と、スクリプトの URL は取り除かれます。`<a href>` には `rel="noopener noreferrer"` が付きます。テキストの子の中のテキストは、常にテキストです: `"&amp;"` は `&amp;` と表示されます。

<a id="events"></a>
### イベント

リスナーは引数を1つ受け取ります。ホストが DOM イベントから作る plist です:

| キー | 値 |
|---|---|
| `:type` | イベントの種類（`"click"`）。 |
| `:value` | `event.target.value` が文字列のとき（input、textarea、select、button）はその値。それ以外は nil。 |
| `:checked` | `event.target.checked` が真偽値のとき（checkbox、radio）はその値。それ以外は nil。 |
| `:key`, `:code` | キーボードイベントの `event.key`、`event.code`。それ以外は nil。 |
| `:alt`, `:ctrl`, `:meta`, `:shift` | `t` または nil。 |
| `:repeat` | キーの自動リピートでは `t`。 |
| `:composing` | インプットメソッドがまだ変換中のとき `t`（変換を確定する Enter）。 |
| `:button` | マウスボタンの番号（0 が主ボタン）。それ以外は nil。 |
| `:x`, `:y` | `clientX`、`clientY`（タッチイベントでは最初のタッチのもの）。それ以外は nil。 |
| `:target` | イベントが起きたノードの番号（`event.target` かその上にある、Lisp が作った最も近いノード）。 |
| `:files` | ファイルを持つ要素（ファイル入力）では、`(:name :size :type)` の plist のベクタ。それ以外は nil。 |
| `:form` | フォームの `submit` イベントでは、そのフィールドを `[NAME VALUE]` のベクタにしたもの（submitter も含みます。ファイルのフィールドはファイル名になります）。[`react-form-value`](#react-form-value) で読みます。それ以外は nil。 |

値が表すのは、イベントが起きた場所である `event.target` です。これはリスナーを持つ要素の子のこともあります。リスナーを持つ要素は、それぞれ自分の DOM リスナーを持ちます。クリックでは、まず子のリスナーが実行され、次にリスナーを持つ祖先のリスナーがそれぞれ実行されます。それぞれが別々の呼び出しと描画になります。実行されるリスナーは、イベントの時点でその要素の props にあるもの（最新の描画のクロージャ）です。

**既定の動作。** Lisp が応答するのはブラウザがイベントを処理した後なので、それを止めるには遅すぎます。Lisp がリッスンしている `submit` イベントについては、ホストが必ず `preventDefault` を呼ぶので、Lisp で処理するフォームがページ遷移することはありません。そのほか、すぐに決めなければならないこと（prevent、stop、キーの絞り込み）はすべて [`react-handler`](#react-handler) で宣言します。`<form>` の中の `<button>` はそのフォームを送信します。それ以外のボタンには `:type "button"` を付けてください。

```elisp
(react-define-component 'Search
  :initial-state (lambda (_props) (list :query "" :submitted nil))
  :render
  (lambda (self)
    (jsx (form (:on-submit (lambda (event)
                             (react-set-state self :submitted (react-form-value event "q"))))
           (input (:name "q" :value (react-state self :query)
                   :on-input (lambda (event) (react-set-state self :query (plist-get event :value)))))
           (button "search")
           (p (:class "result") (or (react-state self :submitted) ""))))))
(react-testing-render (jsx (Search)))
(react-testing-input (react-testing-find :tag 'input) "emacs")
(react-testing-submit (react-testing-find :tag 'form))
(react-testing-text (react-testing-find :class "result"))
;; => "emacs"
```

<a id="svg"></a>
### SVG

`svg` 要素の中では、すべての要素が SVG 名前空間に作られます。中のコンポーネントが後から描画する場合も同じです。`foreignObject` の中では、子は再び HTML になります。属性名は書いたとおりに使われます（`:viewBox`、`:stroke-width`）。`jsx` は [`react-svg-tags`](#react-svg-tags) のタグを知っています。`set` はそこに含まれない（Lisp の関数です）ので、ただのリストの形で書きます。

```elisp
(react-render-to-string (jsx (svg (:viewBox "0 0 10 10" :width 20) (circle (:cx 5 :cy 5 :r 4 :fill "teal")))))
;; => "<svg viewBox=\"0 0 10 10\" width=\"20\"><circle cx=\"5\" cy=\"5\" r=\"4\" fill=\"teal\"></circle></svg>"
```

<a id="components"></a>
## コンポーネント

<a id="react-define-component"></a>
### react-define-component

`(react-define-component NAME &rest SPEC)` → `NAME`

コンポーネント `NAME`（シンボル）を定義します。定義はそのシンボルのプロパティ `react-component` に保存され、以後は要素 `(NAME PROPS CHILD...)` がそれを描画します。`:render` が関数でないときは `(error "Component NAME has no :render function")` を通知します。同じ名前を再び定義すると、マウントされているインスタンスが変わります（[再定義](#redefinition)を参照）。

| キー | 値 | いつ |
|---|---|---|
| `:render` | `(lambda (SELF))` → 要素、要素のリスト（フラグメント）、文字列、数値、または nil（空のテキストノード）。必須です。 | 描画のたび。 |
| `:initial-state` | `(lambda (PROPS))` → 最初の state（plist）。 | 1回だけ。インスタンスが作られたとき、最初の描画の前。 |
| `:did-mount` | `(lambda (SELF))`、またはそのような関数のリスト（順に呼ばれます）。 | 1回だけ。最初の描画の後の flush で。子が親より先。 |
| `:did-update` | `(lambda (SELF PREVIOUS-PROPS PREVIOUS-STATE))`、またはそのリスト。 | 2回目以降の、スキップされなかった各描画の後。親が子より先。 |
| `:will-unmount` | `(lambda (SELF))`、またはそのリスト。 | インスタンスが取り外される前。親が子より先。 |
| `:should-update` | `(lambda (SELF PREVIOUS-PROPS PREVIOUS-STATE))` → nil なら描画をスキップします。`SELF` はすでに新しい props と state を持っています。前の値は、最後に実際に行われた描画が見たものです。 | 2回目以降の各描画の前。 |
| `:pure` | `t`: [`react-shallow-equal`](#react-shallow-equal) で比べて prop のどれかか state が変わったときだけ描画します。 | `:should-update` があるときは無視されます。 |
| `:did-catch` | `(lambda (SELF ERROR))`: エラー境界。`ERROR` はコンディション `(SYMBOL . DATA)` です。 | 下にあるコンポーネントの `:render` がエラーを通知したとき。 |

その他のキーは定義に保存されますが、無視されます。

**props。** コンポーネントは、要素の props の plist を書いたとおりに（`:key` も含めて）受け取り、加えて `:children` として、要素の子を平らにして nil を除いたものを受け取ります（子があるときだけ）。コンポーネント要素の `:ref` は普通の prop で、DOM の ref ではありません（代わりに [`react-make-ref`](#react-make-ref) を渡します）。

```elisp
(react-define-component 'Card
  :render (lambda (self)
            (jsx (section (h2 (react-props self :title)) (react-props self :children)))))
(react-testing-render (jsx (Card (:title "T" :key 7) (p "a") nil (p "b"))))
(react-testing-html)
;; => "<section><h2>T</h2><p>a</p><p>b</p></section>"
(react-props (react-root "#app"))
;; => (:title "T" :key 7 :children ((p nil "a") (p nil "b")))
```

`SELF` を取る関数: [`react-props`](#react-props)、[`react-state`](#react-state)、[`react-set-state`](#react-set-state)、[`react-force-update`](#react-force-update)、[`react-effect`](#react-effect)、[`react-context`](#react-context)、[`react-query`](#react-query)、[`react-ref`](#react-ref)、[`react-make-ref`](#react-make-ref)、[`react-focus`](#react-focus)、[`react-invoke`](#react-invoke)、[`react-set-property`](#react-set-property)、[`react-measure`](#react-measure)、[`react-observe-visible`](#react-observe-visible)。インスタンスはアンマウントされた後も有効ですが、それを描画するものはもうありません。

<a id="skipping-renders"></a>
### 描画のスキップ

`:pure`、`react-shallow-equal`、`react-changed-p` は、値を次のように比べます。文字列は `string=`、数値は `=`、それ以外はすべて `eq` です。同じ `lambda` から作られた2つのクロージャは、捕捉した値がその比較で（1段の深さまで）同じなら同じとみなされます。そのため `(Item (:on-pick (lambda (_event) (pick item))))` は、`item` が同じオブジェクトである限り `:pure` を無効にしません。描画の中で作ったリストを捕捉するクロージャは無効にします。これが働くためには、state は置き換えなければならず、その場で変更してはいけません。

```elisp
(defvar item-renders 0)
(react-define-component 'Item
  :pure t
  :render (lambda (self) (setq item-renders (1+ item-renders)) (format "%s" (react-props self :n))))
(react-define-component 'Items
  :initial-state (lambda (_props) (list :clicks 0 :data (list 1 2)))
  :render (lambda (self)
            (let ((data (react-state self :data)))
              (jsx (div (Item (:n 1 :data data :on-pick (lambda (_event) data)))
                        (Item (:n 2 :data (list 1 2))))))))
(react-testing-render (jsx (Items)))
(setq item-renders 0)
(react-set-state (react-root "#app") :clicks 1)
(react-testing-flush)
item-renders
;; => 1
```

最初の `Item` は描画をスキップしました。2番目は新しいリストを受け取ったので描画しました。

<a id="error-boundaries"></a>
### エラー境界

`:render` の中のエラーは、その上にあって（描画の順で）`:did-catch` を持つ最も近いコンポーネントが捕まえます。失敗したコンポーネントは空のテキストノードを描画し、境界はふつう state を設定して別のものを表示します。境界がないと、エラーは [`react-render-error`](#react-render-error) になり、そのメッセージはそのコンポーネントとその上のコンポーネントの名前を示します。境界が捕まえないのは、イベントハンドラ、`:did-mount`、`:did-update`、エフェクト、タイマーの中のエラーと、描画が返した不正な要素による `Not an element` エラーです。

```elisp
(react-define-component 'Broken :render (lambda (_self) (car 1)))
(react-define-component 'Boundary
  :initial-state (lambda (_props) (list :error nil))
  :did-catch (lambda (self error) (react-set-state self :error error))
  :render (lambda (self)
            (if (react-state self :error)
                (jsx (p (:class "error") (format "Failed: %s" (error-message-string (react-state self :error)))))
              (react-props self :children))))
(react-testing-render (jsx (Boundary (div (Broken)))))
(react-testing-html)
;; => "<p class=\"error\">Failed: Wrong type argument: listp, 1</p>"
(react-testing-render (jsx (div (Broken))))
;; error: react-render-error
```

flush が失敗すると、まだ待っていたもの（dirty なコンポーネント、`:did-mount` と `:did-update` の呼び出し、エフェクト）はキューに残り、次の flush で実行されます。

<a id="react-render-error"></a>
#### react-render-error

`:render` が失敗し、上にあるどの `:did-catch` も捕まえないときに通知されるエラーシンボルです（メッセージは `"Error while rendering"`）。データは1つの文字列 `"MESSAGE, in Card < Page < App"` で、元のメッセージとコンポーネントの経路です。`(cadr err)` がその文字列で、`error-message-string` は `Error while rendering: "..."` を返します。最初の描画で失敗すると、`react-mount` 自体からこのエラーが通知されます。

<a id="redefinition"></a>
### 再定義

すでに定義されている名前について `react-define-component` を評価すると、その名前のマウントされているすべてのインスタンスが新しい定義を受け取り、次の flush で、`:should-update` に関係なく、今ある state のまま再描画されます。`:initial-state` と `:did-mount` は再び実行されず、古い `:did-mount` が始めたタイマーは古いクロージャを呼び続けます。ホストの `load(name, text)` は、この仕組みで動いているページを変更します（elisp-studio がこれを使っています）。

ファイルを読み込み直すと、その中のほかのフォームも評価し直されます。`defun` は関数を置き換え、`defconst` と `setq` は新しい値を設定し、`defvar` は変数がすでに持っている値を保ちます。アプリケーションのデータは `defvar` に（残ります）、定数は `defconst` に置いてください。

<a id="reference"></a>
## リファレンス

<a id="mounting"></a>
### マウント

<a id="react-mount"></a>
#### react-mount

`(react-mount ELEMENT SELECTOR)` → `SELECTOR`

`ELEMENT` を、CSS の `SELECTOR` が指すページの要素の中に描画します。ホストはその要素の子をこれで置き換えます。描画はすぐに実行され、DOM 操作は呼び出しの終わりに送り出されます。同じ `SELECTOR` に再びマウントすると、そこにあるものを差分計算で更新します（型と key が一致するところでは、コンポーネントの state が残ります）。複数のセレクタが、それぞれルートを持てます。ページの何にも一致しないセレクタは、ホストのエラーになります。

```elisp
(react-mount (jsx (p "hello")) "#app")
;; => "#app"
(react-flush)
;; => [["create" 1 "p"] ["text" 2 "hello"] ["insert" 1 2 nil] ["mount" "#app" 1]]
```

<a id="react-unmount"></a>
#### react-unmount

`(react-unmount SELECTOR)` → nil

`react-mount` が `SELECTOR` に描画したものを取り外します。`:will-unmount` とエフェクトのクリーンアップを実行し、ノードを取り除きます。そこに何もなければ何もしません。

<a id="react-root"></a>
#### react-root

`(react-root SELECTOR)` → インスタンスまたは nil

`react-mount` が `SELECTOR` に描画したコンポーネントのインスタンスです。そこに何もないか、ルートがコンポーネントでないときは nil です。コンポーネントの外のコード向けです。

<a id="react-render-to-string"></a>
#### react-render-to-string

`(react-render-to-string ELEMENT)` → 文字列

`ELEMENT` を、ページなしで HTML のテキストにします。サーバーが返す最初の画面に使え、ネイティブの Emacs でも動きます。コンポーネントは初期の state で描画され、`:did-mount`、`:did-update`、エフェクトは実行されません。何もマウントされたまま残らず、操作もキューに入りません。テキストと属性値はエスケープされます（`& < >`、属性ではさらに `"`）。リスナー、`:key`、`:ref`、`:inner-html` は省かれ、`:value` と `:checked` は属性になり、空要素には終了タグが付きません。後でページの `react-mount` がこの HTML を置き換えます（ハイドレーションはありません）。

```elisp
(react-render-to-string (jsx (p "Tom & <Jerry>" (input (:value "x" :checked t)) (br))))
;; => "<p>Tom &amp; &lt;Jerry&gt;<input value=\"x\" checked><br></p>"
```

<a id="react-html"></a>
#### react-html

`(react-html SELECTOR)` → 文字列または nil

`SELECTOR` にマウントされているものを、保留中の描画を実行した後で、Lisp 自身の木から HTML のテキストにしたものです（キューにある操作は取り出しません）。`react-render-to-string` と同じようにエスケープされます。テストとデバッグ用です。

<a id="react-inspect"></a>
#### react-inspect

`(react-inspect &optional SELECTOR)` → リスト

`SELECTOR`（または全体）にマウントされているコンポーネントを、親から先に並べたものです。各要素は `(:component NAME :depth N :props PROPS :state STATE)` です。

```elisp
(react-testing-render (jsx (Card (:title "x"))))
(react-inspect "#app")
;; => ((:component Card :depth 0 :props (:title "x") :state nil))
```

<a id="react-reset"></a>
#### react-reset

`(react-reset)` → nil

マウントされているものと保留中のものを、すべて忘れます。ルート、キューにある操作、dirty なインスタンス、リクエスト、ストレージのコピー、ストレージとアドレスの監視、クエリ、アドレス、ロケールです。`:will-unmount` は実行されません。コンポーネントの定義は残ります。テスト用です（`react-testing-reset` がこれを呼びます）。

<a id="constants"></a>
### 定数

<a id="react-html-tags"></a>
#### react-html-tags

`jsx` がマークアップとして読む HTML 要素です（111個のシンボル）: `a abbr address area article aside audio b bdi bdo blockquote body br button canvas caption cite code col colgroup data datalist dd del details dfn dialog div dl dt em embed fieldset figcaption figure footer form h1 h2 h3 h4 h5 h6 head header hgroup hr html i iframe img input ins kbd label legend li link main map mark menu meta meter nav noscript object ol optgroup option output p picture pre progress q rp rt ruby s samp script search section select slot small source span strong style sub summary sup table tbody td template textarea tfoot th thead time title tr track u ul var video wbr`。それ以外の小文字のタグはただのリストの形で書きます。カスタム要素なら、大文字で始めてハイフンを入れた名前で書きます。

<a id="react-svg-tags"></a>
#### react-svg-tags

`jsx` がマークアップとして読む SVG 要素です（38個のシンボル）: `svg g defs symbol use path circle ellipse line polyline polygon rect text tspan textPath linearGradient radialGradient stop clipPath mask pattern marker image foreignObject animate animateMotion animateTransform desc filter feBlend feColorMatrix feComposite feFlood feGaussianBlur feMerge feMergeNode feOffset feDropShadow`。`set` は含みません（Lisp の関数です）。

```elisp
(list (length react-html-tags) (length react-svg-tags) (memq 'set react-svg-tags))
;; => (111 38 nil)
```

<a id="host-entry-points"></a>
### ホストの入口

これらはホストが呼ぶもので、アプリケーションが呼ぶことはまれです。どれも [`react-flush`](#react-flush) の DOM 操作のベクタを返します。

<a id="react-flush"></a>
#### react-flush

`(react-flush)` → 操作のベクタ

保留中の描画（と、それが引き起こす `:did-mount`、`:did-update`、エフェクトの呼び出し）を終え、前回の呼び出し以後の操作を古い順に返します。各操作はベクタです:

| 操作 | 意味 |
|---|---|
| `["create" ID TAG]`, `["create" ID TAG "svg"]` | 要素を作ります（SVG 名前空間に）。 |
| `["text" ID STRING]`, `["set-text" ID STRING]` | テキストノードを作ります。そのテキストを変更します。 |
| `["attr" ID NAME VALUE]` | 属性を設定します。`t` は空、nil は属性を取り除きます。 |
| `["prop" ID NAME VALUE]` | DOM プロパティを設定します（`value`、`checked`、`react-set-property` が扱うもの）。 |
| `["listen" ID EVENT OPTIONS]`, `["unlisten" ID EVENT]` | ホストのリスナーを追加または削除します。`OPTIONS` は `react-handler` から来るもの、または nil。 |
| `["insert" PARENT-ID ID BEFORE-ID]`, `["before" ID BEFORE-ID]` | ノードを親に入れます（`BEFORE-ID` の前、nil なら末尾に）。ノードを別のノードの前に置きます（フラグメント）。 |
| `["replace" OLD-ID ID]`, `["remove" ID]` | ノードを置き換えます。ノードを取り除きます。 |
| `["mount" SELECTOR ID...]` | ルートのノードがページの要素に入ります。 |
| `["html" ID HTML]` | 無害化した HTML をノードに入れます（`:inner-html`）。 |
| `["invoke" ID METHOD ARG...]` | ノードのメソッドを呼びます。 |
| `["call" REQUEST COMMAND ARGUMENT]` | 何かを行い、後で `react-host-reply` で答えます。 |
| `["tell" COMMAND ARGUMENT]` | 何かを行います。答えはありません。 |
| `["cancel" REQUEST]` | リクエストを止めます。 |

<a id="react-dispatch-event"></a>
#### react-dispatch-event

`(react-dispatch-event DOM-ID NAME EVENT)` → 操作

ノード `DOM-ID` が DOM イベント `NAME`（`"click"`）を plist `EVENT` とともに受け取ったときに呼びます。その要素に現在の `:on-NAME` リスナーがあればそれを実行し、flush します。

<a id="react-host-reply"></a>
#### react-host-reply

`(react-host-reply REQUEST OK VALUE)` → 操作

`REQUEST` に対するページの答えです。それを待っている関数を `OK`（成功なら non-nil）と `VALUE` で呼び、flush します。保持されないリクエスト（`KEEP` なしの `react-host-call`）は、最初の答えの後に忘れられます。未知のリクエストや取り消されたリクエストは無視されます。

<a id="react-host-replies"></a>
#### react-host-replies

`(react-host-replies REPLIES)` → 操作

`REPLIES` は `[REQUEST OK VALUE]` のベクタで、Lisp が忙しい間に届いた答えです。待っている関数をすべて実行し、それから1回だけ描画します。1つでエラーが起きても、ほかは止まりません。すべてが実行された後に最初のエラーが通知され、それらが変更したものは次の flush で描画されます。

<a id="react-page-call"></a>
#### react-page-call

`(react-page-call NAME ARGS)` → 操作

`window.elispReact.send(NAME, ...ARGS)` が呼ぶものです。`(apply (intern NAME) ARGS)` を実行し（`ARGS` は JSON 値のベクタ）、flush します。[ページの JavaScript を呼ぶ](#calling-page-javascript)を参照してください。

<a id="state"></a>
### state

<a id="react-props"></a>
#### react-props

`(react-props SELF &optional KEY)` → props の plist、または `KEY` の値

<a id="react-state"></a>
#### react-state

`(react-state SELF &optional KEY)` → state の plist、または `KEY` の値

state は `:initial-state` が返したもので、`react-set-state` によってのみ変わります。

<a id="react-set-state"></a>
#### react-set-state

`(react-set-state SELF &rest CHANGES)` → nil

`CHANGES` は state にマージされる plist（`(react-set-state self :count 1 :label "x")`）か、現在の state を受け取ってその plist を返す関数1つです。新しい plist がすぐに設定され、古いものは変更されません。マウントされているインスタンスは、呼び出しの終わりに描画されます。複数回呼んでも描画は1回です。アンマウントされたインスタンスは新しい state を受け取りますが、描画はされません。

```elisp
(react-define-component 'Tally
  :initial-state (lambda (_props) (list :count 0 :label "n"))
  :render (lambda (self) (format "%s=%d" (react-state self :label) (react-state self :count))))
(react-testing-render (jsx (Tally)))
(let ((self (react-root "#app")))
  (react-set-state self :count 1)
  (react-set-state self (lambda (state) (list :count (+ 10 (plist-get state :count)))))
  (list (react-state self) (react-testing-html)))
;; => ((:count 11 :label "n") "n=0")
(react-testing-flush)
(react-testing-html)
;; => "n=11"
```

<a id="react-plist-with"></a>
#### react-plist-with

`(react-plist-with PLIST &rest CHANGES)` → 新しい plist

`CHANGES` のキーを設定した `PLIST` です。`PLIST` 自体は変更されません。新しいキーは末尾に付きます。state に持つレコードを変更するときに使います。

```elisp
(let ((todo '(:id 1 :text "a" :done nil)))
  (list (react-plist-with todo :done t :tag "x") todo))
;; => ((:id 1 :text "a" :done t :tag "x") (:id 1 :text "a" :done nil))
```

<a id="react-force-update"></a>
#### react-force-update

`(react-force-update SELF)` → nil

`:should-update` の結果にかかわらず、この呼び出しの終わりに `SELF` を再描画します。props と state 以外のものを読むコンポーネント向けです。

<a id="react-refresh"></a>
#### react-refresh

`(react-refresh &optional TYPE)` → nil

マウントされているすべてのインスタンス（指定したときは、コンポーネント `TYPE`（シンボル）のインスタンス）を、`:should-update` に関係なく、この呼び出しの終わりに再描画します。グローバルなデータが変わった後に使います。

<a id="react-shallow-equal"></a>
#### react-shallow-equal

`(react-shallow-equal A B)` → plist `A` と `B` が同じキーに同じ値を持つとき non-nil。値は[描画のスキップ](#skipping-renders)のとおりに比べます。

```elisp
(list (react-shallow-equal '(:a "x" :b 1) '(:a "x" :b 1)) (react-shallow-equal '(:a (1)) '(:a (1))))
;; => (t nil)
```

<a id="react-changed-p"></a>
#### react-changed-p

`(react-changed-p NEW OLD &rest KEYS)` → 2つの plist が `KEYS` のどれかで異なるとき non-nil

`:should-update` で、描画が使う props だけを比べるためのものです。関数の prop を比較から外しても、ハンドラがそれをイベントの時点で読むなら（`(funcall (react-props self :on-change) ...)`）安全です。スキップされたコンポーネントも、新しい props は受け取るからです。

```elisp
(react-define-component 'TodoRow
  :should-update (lambda (self previous-props previous-state)
                   (or (not (eq (react-state self) previous-state))
                       (react-changed-p (react-props self) previous-props :todo)))
  :render (lambda (self) (jsx (li (plist-get (react-props self :todo) :text)))))
(react-changed-p '(:a 1 :b (x)) '(:a 1 :b (x)) :a)
;; => nil
```

<a id="effects"></a>
### エフェクト

<a id="react-effect"></a>
#### react-effect

`(react-effect SELF KEY DEPS FUNCTION)` → nil

`SELF` の描画の中で呼びます。`KEY`（シンボル。`eq` で比べます）は、そのインスタンスのエフェクトの中でこのエフェクトを区別する名前です。`FUNCTION` は引数を取らず、`DEPS`（任意のデータ）が前回の実行時の deps と `equal` でないとき、描画の後（`:did-mount` と `:did-update` の後）に実行されます。最初は必ず実行されます。`FUNCTION` が関数を返すと、それがクリーンアップになります。クリーンアップは、`FUNCTION` が再び実行される前と、インスタンスが取り外されるときに実行されます。`DEPS` が nil なら1回だけ実行されます。`:should-update` がスキップした描画はエフェクトに届かず、エフェクトは前回の実行のままです。state を持つロジックは、複数のコンポーネントが呼ぶ普通の関数になります:

```elisp
(defun my-use-interval (self ms function)
  "Call FUNCTION every MS milliseconds while SELF is mounted."
  (react-effect self 'interval ms
    (lambda ()
      (let ((timer (react-set-interval ms function)))
        (lambda () (react-clear-timer timer))))))

(react-define-component 'Ticker
  :initial-state (lambda (_props) (list :ticks 0))
  :render (lambda (self)
            (my-use-interval self 1000 (lambda () (react-set-state self :ticks (1+ (react-state self :ticks)))))
            (format "%d" (react-state self :ticks))))
(react-testing-render (jsx (Ticker)))
(react-testing-time-passes)
(react-testing-time-passes)
(list (react-testing-html) (mapcar #'cadr react-testing-requests))
;; => ("2" ("interval"))
(react-unmount "#app")
(react-testing-flush)
react-testing-requests
;; => nil
```

<a id="context"></a>
### コンテキスト

<a id="react-provide"></a>
#### react-provide

`(react-provide KEY VALUE CHILD)` → 要素

`CHILD`（要素、または要素のリスト）を描画し、その下にあるすべてのコンポーネントに、どれだけ深くても、`VALUE` を `KEY`（任意のデータ。`equal` で比べます）の下で渡す要素です。`(react-provider (:context KEY :value VALUE) CHILD)` と同じものです。

<a id="react-context"></a>
#### react-context

`(react-context SELF KEY &optional DEFAULT)` → 値

`SELF` の上にある、`KEY` の最も近い `react-provide` の `VALUE` です。それがなければ `DEFAULT` です。`SELF` は読み手になります。プロバイダが異なる値（文字列と数値は値で、ほかのデータは同一性で比べます）で描画すると、すべての読み手が再描画されます。描画をスキップしたコンポーネントの下にあっても同じです。「上」は描画の順に従います。あるコンポーネントを生み出した描画を持つコンポーネントが、その親です。

```elisp
(react-define-component 'Label
  :pure t
  :render (lambda (self) (jsx (span (react-context self 'language "none")))))
(react-define-component 'Middle :pure t :render (lambda (_self) (jsx (p (Label)))))
(react-define-component 'LanguageApp
  :initial-state (lambda (_props) (list :language "ja"))
  :render (lambda (self)
            (jsx (div (react-provide 'language (react-state self :language) (jsx (Middle)))
                      (Label)))))
(react-testing-render (jsx (LanguageApp)))
(react-testing-html)
;; => "<div><p><span>ja</span></p><span>none</span></div>"
(react-set-state (react-root "#app") :language "en")
(react-testing-flush)
(react-testing-html)
;; => "<div><p><span>en</span></p><span>none</span></div>"
```

<a id="react-provider"></a>
#### react-provider

`react-provide` が返す要素の、組み込みコンポーネントです。props は `:context` と `:value` です。これを直接書かずに `react-provide` を使ってください。

<a id="refs-and-dom-nodes"></a>
### ref と DOM ノード

`:ref` は、DOM 要素に、それを描画したコンポーネントにとっての名前を付けます。以下の関数は、描画の DOM 操作の後でその要素に作用します。呼ばれた時点で操作を出し、ホストは操作を順に適用するからです。`:did-mount`、`:did-update`、エフェクト、またはすでに存在する要素についてのハンドラの中で呼んでください。コンポーネントにその ref の要素がなければ、どれも何もしません（nil を返します）。

<a id="react-ref"></a>
#### react-ref

`(react-ref SELF NAME)` → マウントされている要素、または nil

`SELF` が `:ref NAME`（`equal` で比べます）を付けて描画した要素です。値の中身は不透明で、[`react-node-id`](#react-node-id) と、`react-fetch` の `:file`、`:form` に使えます。

<a id="react-make-ref"></a>
#### react-make-ref

`(react-make-ref SELF NAME)` → ref

`SELF` が下のコンポーネントに渡す ref です。受け取ったコンポーネントは、それを要素に付けます: `(input (:ref (react-props self :input-ref)))`。するとその要素は、`SELF` が描画したかのように、`SELF` の ref `NAME` になります。

```elisp
(react-define-component 'Field
  :render (lambda (self) (jsx (input (:ref (react-props self :input-ref))))))
(react-define-component 'SearchForm
  :did-mount (lambda (self) (react-focus self "search"))
  :render (lambda (self) (jsx (form (Field (:input-ref (react-make-ref self "search")))))))
(react-testing-render (jsx (SearchForm)))
react-testing-invoked
;; => ((2 "focus"))
```

<a id="react-node-id"></a>
#### react-node-id

`(react-node-id REF)` → 整数、または nil

`REF`（`react-ref` の値）の DOM ノードを、ページが識別するための番号です。ページのコマンドは `node(id)` でそのノードを得ます。

<a id="react-focus"></a>
#### react-focus

`(react-focus SELF NAME)` → nil

`:ref NAME` の要素にキーボードフォーカスを与えます。`(react-invoke SELF NAME "focus")` と同じです。

```elisp
(react-focus self "field")
(react-flush)
;; => [["invoke" 2 "focus"]]
```

<a id="react-invoke"></a>
#### react-invoke

`(react-invoke SELF NAME METHOD &rest ARGS)` → nil

`:ref NAME` の DOM ノードで、`METHOD` を `ARGS`（JSON 値）とともに呼びます。`METHOD` は `"focus"`、`"blur"`、`"select"`、`"click"`、`"scrollIntoView"`、`"scrollTo"`、`"scrollBy"`、`"setSelectionRange"`、`"showModal"`、`"show"`、`"close"`、`"requestSubmit"`、`"reset"`、`"reportValidity"`、`"setCustomValidity"`、`"play"`、`"pause"`、`"load"`、`"requestFullscreen"`、`"showPicker"` のどれかで、それ以外はホストのエラーになります。ノードが持たないメソッドや、メソッドが reject した promise（ユーザーの操作なしの `play`）は、コンソールの警告になります。

```elisp
(react-invoke self "field" "setSelectionRange" 0 3)
(react-invoke self "field" "scrollIntoView" '(:block "center"))
(react-flush)
;; => [["invoke" 2 "setSelectionRange" 0 3] ["invoke" 2 "scrollIntoView" (:block "center")]]
```

`(react-invoke self "dialog" "showModal")` で開いた `<dialog>` は本物のモーダルです。背後のページは操作を受け付けなくなり、フォーカスはその `:autofocus` のフィールドに移り、Escape で閉じて `:on-close` が発火します。

<a id="react-set-property"></a>
#### react-set-property

`(react-set-property SELF NAME PROPERTY VALUE)` → nil

`:ref NAME` のノードの DOM プロパティ `PROPERTY` を設定します。`PROPERTY` は `"indeterminate"`、`"selectedIndex"`、`"open"`、`"muted"`、`"volume"`、`"currentTime"`、`"playbackRate"`、`"loop"`、`"scrollTop"`、`"scrollLeft"` のどれかです（`value` と `checked` は props です）。それ以外は、ホストが警告を出して無視します。`t` と nil は `true` と `false` になります。

<a id="react-measure"></a>
#### react-measure

`(react-measure SELF NAME FUNCTION)` → リクエスト、または nil

DOM 操作が適用された後で `:ref NAME` のノードを測り、`FUNCTION` を plist とともに呼びます。plist には、ボックスの `(:x :y :width :height)`、`(:scrollTop :scrollLeft :scrollWidth :scrollHeight :clientWidth :clientHeight)`、audio と video ではさらに `(:currentTime :duration :paused)` が入ります。

<a id="react-observe-visible"></a>
#### react-observe-visible

`(react-observe-visible SELF NAME FUNCTION &rest OPTIONS)` → リクエスト、または nil

`:ref NAME` のノードが見える範囲に入ったときと出たとき（`IntersectionObserver`）、そして最初に1回、`FUNCTION` を `VISIBLE`（`t` または nil）と `RATIO`（数値）で呼びます。`OPTIONS`: `:margin "200px"`（その分だけ早く見えたとみなします）、`:threshold 0.5`。要素がページに出た後（`:did-mount`）で使ってください。`react-cancel` で止まります。

<a id="events-and-forms"></a>
### イベントとフォーム

<a id="react-handler"></a>
#### react-handler

`(react-handler FUNCTION &rest OPTIONS)` → `react-handler`

Lisp が応答する前にホストが処理する、リスナーの prop です。`FUNCTION` は、普通の関数の prop と同じようにイベントを受け取ります。`OPTIONS`:

| オプション | ページでの効果 |
|---|---|
| `:keys LIST` | `event.key` が `LIST`（`'("Enter" "/")`）にあるイベントだけが Lisp に届き、それらだけが prevent や stop の対象になります。 |
| `:self t` | この要素自身のイベントだけで、子のイベントは対象外です。 |
| `:prevent t` | `preventDefault`: リンクをたどらず、キーを入力せず、スクロールしません。 |
| `:stop t` | `stopPropagation`: 親のリスナーには届きません。 |
| `:capture t` | キャプチャフェーズでリッスンします。 |
| `:passive t` | パッシブなリスナーにします。 |
| `:throttle MS` | `MS` ミリ秒ごとに最大1つのイベント。連続したイベントの最後のものは、終わりに送られます。 |

その他のオプションは無視されます。オプションが変わったリスナーは、リッスンし直されます。オプションが同じで関数だけが新しい場合、DOM 操作は発生しません。この構造体には、アクセサ `react-handler-function` と `react-handler-options`、述語 `react-handler-p` があります。

```elisp
(defun my-link (href text)
  "A link that changes the address without loading a page."
  (jsx (a (:href href :on-click (react-handler (lambda (_event) (react-navigate href)) :prevent t))
         text)))
(react-mount (my-link "/about" "About") "#app")
(react-flush)
;; => [["create" 1 "a"] ["attr" 1 "href" "/about"] ["listen" 1 "click" (:prevent t)] ["text" 2 "About"] ["insert" 1 2 nil] ["mount" "#app" 1]]
(react-handler-options (react-handler #'ignore :keys '("Enter") :prevent t))
;; => (:keys ("Enter") :prevent t)
```

<a id="react-form-value"></a>
#### react-form-value

`(react-form-value EVENT NAME)` → 文字列、または nil

submit の `EVENT` が送ったフォームの、フィールド `NAME` の値です（その名前の最初のもの）。ファイルのフィールドではファイル名になります。

<a id="react-form-values"></a>
#### react-form-values

`(react-form-values EVENT NAME)` → 文字列のリスト

フィールド `NAME` のすべての値です。チェックボックスや、複数選択の select に使います。

```elisp
(let ((event '(:type "submit" :form [["q" "括弧"] ["tag" "a"] ["tag" "b"]])))
  (list (react-form-value event "q") (react-form-values event "tag") (react-form-value event "none")))
;; => ("括弧" ("a" "b") nil)
```

<a id="timers"></a>
### タイマー

<a id="react-set-timeout"></a>
#### react-set-timeout

`(react-set-timeout MILLISECONDS FUNCTION)` → リクエスト

`MILLISECONDS` の後に、`FUNCTION` を引数なしで1回呼びます。

<a id="react-set-interval"></a>
#### react-set-interval

`(react-set-interval MILLISECONDS FUNCTION)` → リクエスト

取り消されるまで、`MILLISECONDS` ごとに `FUNCTION` を引数なしで呼びます。`:did-mount`（またはエフェクト）で始め、`:will-unmount`（またはエフェクトのクリーンアップ）で取り消してください。

<a id="react-clear-timer"></a>
#### react-clear-timer

`(react-clear-timer REQUEST)` → nil。[`react-cancel`](#react-cancel) の別名です。

<a id="react-cancel"></a>
#### react-cancel

`(react-cancel REQUEST)` → nil

`REQUEST` を忘れ（その関数は呼ばれなくなります）、ホストにそれを止めるよう伝えます。タイマーの解除、fetch の中断、接続の切断、ページのリスナーやオブザーバーの削除、またはページのコマンドが返した取り消し関数の呼び出しです。`REQUEST` が nil なら何もしません。

```elisp
(let ((timer (react-set-timeout 500 #'ignore)))
  (react-clear-timer timer)
  (react-flush))
;; => [["call" 1 "timeout" 500] ["cancel" 1]]
```

<a id="network"></a>
### ネットワーク

<a id="react-fetch"></a>
#### react-fetch

`(react-fetch URL &rest OPTIONS)` → リクエスト

ブラウザの `fetch` で `URL` にリクエストします。`OPTIONS`:

| オプション | |
|---|---|
| `:method STRING` | 既定は `"GET"`。 |
| `:headers PLIST` | `(:content-type "application/json" :authorization "Bearer ...")`。 |
| `:body STRING` | ボディ。 |
| `:file REF` | `:body` の代わりに、ファイル入力 `REF`（`(react-ref SELF NAME)`）で選ばれた最初のファイルを、大きさにかかわらずそのまま送ります。ファイルが選ばれていなければ、`:catch` が `"No file is chosen"` を受け取ります。 |
| `:form LIST` | `:body` の代わりに、`NAME VALUE ...` を `multipart/form-data` として送ります。`VALUE` は文字列か、ファイル入力への ref です（ref ならそのファイルが送られます）。 |
| `:as 'base64` | ボディが `:text` ではなく `:base64` で届きます（バイト列。[`react-response-bytes`](#react-response-bytes) を参照）。これがなければ、ボディは UTF-8 としてデコードされます。 |
| `:credentials`, `:cache`, `:redirect`, `:mode`, `:keepalive`, `:priority`, `:referrerPolicy` | そのまま `fetch` に渡されます（シンボルの値はその名前として）。`:credentials "include"` で、別のオリジンにも cookie を送ります。 |
| `:then FUNCTION` | `(RESPONSE)`: plist `(:status 200 :ok t :url "..." :redirected nil :headers (:content-type "..." ...) :text "...")`。HTTP のエラーステータスもレスポンスで、`:ok` が nil になります。ヘッダ名は小文字です。 |
| `:catch FUNCTION` | `(MESSAGE)`: レスポンスがまったくなかった場合（オフライン、接続拒否、CORS）。`:catch` がなければ、メッセージは `message` で表示されます。 |

ページ自身のオリジンの cookie は、すべてのリクエストに付きます（ブラウザの既定）。`react-cancel` で中断します。

```elisp
(react-fetch "/api/notes" :method "POST" :headers '(:content-type "application/json") :body "{\"text\":\"x\"}"
             :then (lambda (response) (message "%s" (plist-get response :status))))
;; => 1
(react-flush)
;; => [["call" 1 "fetch" (:url "/api/notes" :method "POST" :headers (:content-type "application/json") :body "{\"text\":\"x\"}")]]
```

<a id="react-response-json"></a>
#### react-response-json

`(react-response-json RESPONSE)` → Lisp のデータ

`RESPONSE` の `:text` を JSON として解析したものです。オブジェクトは plist、配列はベクタ、`null` と `false` は nil、`true` は `t` になります。不正な JSON では `json-parse-error` を通知します。

```elisp
(react-response-json '(:text "{\"a\":null,\"b\":false,\"c\":true,\"d\":[1,{\"e\":\"x\"}]}"))
;; => (:a nil :b nil :c t :d [1 (:e "x")])
```

<a id="react-response-header"></a>
#### react-response-header

`(react-response-header RESPONSE NAME)` → 文字列、または nil

`RESPONSE` のヘッダ `NAME`（大文字小文字は問いません）です。CORS がページに公開しないヘッダは含まれません。

<a id="react-response-bytes"></a>
#### react-response-bytes

`(react-response-bytes RESPONSE)` → ユニバイト文字列

`:as 'base64` で取得したレスポンスのボディです。

<a id="react-websocket"></a>
#### react-websocket

`(react-websocket URL &rest OPTIONS)` → 接続（リクエスト）

`URL`（`ws:`、`wss:`、またはこのサイトのパス。パスは `ws:`/`wss:` に変換されます）への WebSocket を開きます。`OPTIONS`: `:on-open ()`、メッセージごとの `:on-message (TEXT)`（バイナリのメッセージでは nil）、`:on-close (CODE REASON)`、`:on-error ()`、`:protocols LIST`。close の後には何も来ません。`react-cancel` で閉じます。これは `:will-unmount` で行ってください。メッセージ1つごとに、Lisp の呼び出し1回と描画1回になります。

<a id="react-websocket-send"></a>
#### react-websocket-send

`(react-websocket-send CONNECTION TEXT)` → nil

この呼び出しの操作が適用された後で、`TEXT` を送ります。開いていない接続では、ホストはコンソールに警告を出し、何も送りません。

<a id="react-event-source"></a>
#### react-event-source

`(react-event-source URL &rest OPTIONS)` → 接続

`URL` の Server-Sent Events です。`OPTIONS`: plist `(:type "message" :data "..." :id ...)` を受け取る `:on-message (EVENT)`、`:events LIST`（ほかに受け取るイベント名。その `:type` はその名前です）、`:on-open ()`、`:on-error ()`（接続が切れたとき。ブラウザが自分で再接続します）、`:on-close (nil nil)`（ブラウザが再接続を諦めたとき）、`:with-credentials t`。`react-cancel` で閉じます。

<a id="storage"></a>
### ストレージ

ページの `localStorage` で、印字できる Lisp のデータなら何でも保持します。ホストは開始時に Lisp にそのコピーを渡すので、読み出しはすぐに終わります。書き込みはコピーを変更し、ページに伝えます。キーは文字列です。値は `prin1` で印字し、`read` で読み戻します。リスト、文字列、数値、シンボル、ベクタは使えますが、バッファなど読み戻せないオブジェクトは使えません。

<a id="react-storage-get"></a>
#### react-storage-get

`(react-storage-get KEY &optional DEFAULT)` → 値、または `DEFAULT`

値が `MAX-AGE` 付きで保存されていて、それが過ぎたときも `DEFAULT` です。

<a id="react-storage-set"></a>
#### react-storage-set

`(react-storage-set KEY VALUE &optional MAX-AGE)` → `VALUE`

`VALUE` を `KEY` の下に保存し、そこにあるもの（その間に別のタブが保存したものも）を置き換えます。印字したテキストが変わらない値は、書き直されません。`MAX-AGE`（秒）を付けると、値はその時間が経った後に忘れられます。`react-storage-get` はそれを返さなくなり、後の開始時に削除されます。

```elisp
(react-storage-set "todos" '((:id 1 :text "a")))
;; => ((:id 1 :text "a"))
(react-storage-get "todos")
;; => ((:id 1 :text "a"))
(react-flush)
;; => [["tell" "storage-set" (:key "todos" :value "((:id 1 :text \"a\"))")]]
(react-storage-get "missing" 'none)
;; => none
```

<a id="react-storage-remove"></a>
#### react-storage-remove

`(react-storage-remove KEY)` → nil

<a id="react-storage-watch"></a>
#### react-storage-watch

`(react-storage-watch KEY FUNCTION)` → ハンドル

ページの別のタブが `KEY` を変更したとき、新しい値（削除したときは nil）で `FUNCTION` を呼びます。Lisp のコピーは、すでに新しい値を持っています。タブ間でリストを共有するときは、書き込む前にマージしてください。または state を設定して再描画します。

<a id="react-storage-unwatch"></a>
#### react-storage-unwatch

`(react-storage-unwatch HANDLE)` → nil

監視 `HANDLE` を止めます（`:will-unmount` で）。

<a id="query-cache"></a>
### クエリキャッシュ

コンポーネントが読み込むデータを、コンポーネントの外でキーごとに保持します。同じキーを求めるコンポーネントは1つのリクエストと1つの結果を共有し、戻ってきたコンポーネントはデータをすぐに表示し、キーは古くなったとき（stale）または無効化されたときに読み込み直されます。キーが追い出されることはありません。

<a id="react-query"></a>
#### react-query

`(react-query SELF KEY LOADER &rest OPTIONS)` → `(:status STATUS :data DATA :error ERROR :fetching BOOL)`

描画の中で呼びます。`KEY` は `equal` で比べる任意のデータで、たとえば `("videos" "home")` です。`LOADER` は引数のない関数で、`(RESOLVE REJECT)` の関数を返します: `(lambda () (react-fetch-async "/videos.json"))`。タスク（`react-async`）はここでは受け付けません。`STATUS` は `loading`（まだデータがない）、`success`、`error` のどれかです。`:data` は最後に成功したデータで、キーを読み込み直している間（`:fetching t`）も残ります。`:error` は最後の失敗のメッセージです。`SELF` が初めて `KEY` を求めたとき、キーが `:stale-ms`（`OPTIONS`。既定は 0 で、常に）より古ければ読み込みます。`SELF` のその後の描画は読むだけです。キーのデータまたは状態が変わるたびに、`:pure` かどうかにかかわらず `SELF` は再描画されます。データを持っていたキーの裏での読み込みが失敗した場合は `success` のままで、`:error` が設定されます。

```elisp
(react-define-component 'Videos
  :render (lambda (self)
            (let ((query (react-query self '("videos" "home")
                                      (lambda () (react-fetch-async "/videos.json"))
                                      :stale-ms 60000)))
              (pcase (plist-get query :status)
                ('loading (jsx (p "Loading…")))
                ('error (jsx (p (:class "error") (plist-get query :error))))
                (_ (jsx (ul (mapcar (lambda (title) (jsx (li (:key title) title)))
                                    (react-response-json (plist-get query :data))))))))))
(react-testing-render (jsx (Videos)))
(react-testing-html)
;; => "<p>Loading…</p>"
(react-testing-answer-fetch 200 "[\"a\",\"b\"]")
(react-testing-html)
;; => "<ul><li>a</li><li>b</li></ul>"
```

<a id="react-invalidate"></a>
#### react-invalidate

`(react-invalidate PREFIX)` → nil

`PREFIX` であるキー、またはリスト `PREFIX` で始まるリストであるキーを、すべて古いもの（stale）にします。途中の答えは捨てられます。マウントされているコンポーネントが読んでいるキーは、すぐに読み込み直されます（その間、古いデータは残ります）。その読み込み直しが失敗すると、状態は `error` になり、古い `:data` は残ったままです。

<a id="react-query-set"></a>
#### react-query-set

`(react-query-set KEY DATA)` → `DATA`

読み込んだかのように、`DATA` を `KEY` の下に置きます（楽観的な更新、またはそれを変更したリクエストの答え）。それを読んでいるコンポーネントは再描画されます。

<a id="react-query-data"></a>
#### react-query-data

`(react-query-data KEY)` → データ、または nil

`KEY` を、購読せずに読みます。

<a id="address-and-history"></a>
### アドレスと履歴

<a id="react-location"></a>
#### react-location

`(react-location &optional PART)` → `(:href :pathname :search :hash)`、または1つの `PART`

ページのアドレスです。起動時から分かっているので、描画の中で読めます。ホストの `"memory"` モードでは、`:href` はパス、クエリ、ハッシュだけです。読んでも購読にはなりません。変化したときにコンポーネントが再描画されるのは、ウォッチャーを通したときだけです。

<a id="react-location-watch"></a>
#### react-location-watch

`(react-location-watch FUNCTION)` → ハンドル

アドレスが変わったときに、新しいアドレスの plist を渡して `FUNCTION` を呼びます。変わるのは、戻る・進む、ハッシュの変化（`#...` へのリンク）、オリジン内での `react-navigate` のときです。

```elisp
(react-define-component 'Router
  :render (lambda (self)
            (react-effect self 'location nil
              (lambda ()
                (let ((handle (react-location-watch (lambda (_location) (react-force-update self)))))
                  (lambda () (react-location-unwatch handle)))))
            (pcase (react-location :hash)
              ("#/about" (jsx (h1 "About")))
              (_ (jsx (h1 "Home"))))))
(react-mount (jsx (Router)) "#app")
(react-testing-flush)
(react-testing-location "http://localhost/#/about")
(react-testing-html)
;; => "<h1>About</h1>"
```

<a id="react-location-unwatch"></a>
#### react-location-unwatch

`(react-location-unwatch HANDLE)` → nil

<a id="react-navigate"></a>
#### react-navigate

`(react-navigate URL &optional REPLACE)` → nil

`URL` へ移動します。履歴に新しい項目を加えるか、`REPLACE` があれば現在の項目を変更します。ページのオリジン内ではページはそのままで（`pushState`/`replaceState`）、アドレスのウォッチャーが、それ専用の呼び出しの中で実行されます。別のオリジンの場合は、そのアドレスを読み込みます。

<a id="react-history-go"></a>
#### react-history-go

`(react-history-go DELTA)` → nil

履歴の中を `DELTA` 項目だけ移動します。-1 が「戻る」です。

<a id="react-url-query"></a>
#### react-url-query

`(react-url-query SEARCH)` → alist

クエリ文字列 `SEARCH`（`?` はあってもなくてもかまいません）を `(("NAME" . "VALUE")...)` にしたものです。`%XX` のエスケープは UTF-8 として読み、`+` は空白です。`=` のない名前の値は `""` です。

```elisp
(react-url-query "?q=%E6%8B%AC+x&page=2&flag")
;; => (("q" . "括 x") ("page" . "2") ("flag" . ""))
```

<a id="react-set-title"></a>
#### react-set-title

`(react-set-title TEXT)` → nil

`TEXT` を文書のタイトルにします。

<a id="react-set-meta"></a>
#### react-set-meta

`(react-set-meta NAME CONTENT)` → nil

`<meta>` の `NAME`（`"description"`。`og:...`、`article:...` などは `property` の meta です）を `CONTENT` にします。nil なら削除します。

```elisp
(react-navigate "#/watch?v=b")
(react-navigate "/elsewhere" t)
(react-history-go -1)
(react-set-title "Parens")
(react-set-meta "og:title" "A video")
(react-flush)
;; => [["tell" "navigate" (:url "#/watch?v=b" :replace nil)] ["tell" "navigate" (:url "/elsewhere" :replace t)] ["tell" "history-go" (:delta -1)] ["tell" "title" (:text "Parens")] ["tell" "meta" (:name "og:title" :content "A video")]]
```

<a id="page-events"></a>
### ページのイベント

<a id="react-listen-page"></a>
#### react-listen-page

`(react-listen-page TARGET EVENT FUNCTION &rest OPTIONS)` → リクエスト

`TARGET`（`window` または `document`。シンボルか文字列）の `EVENT`（`"keydown"`、`"resize"`、`"scroll"`、`"visibilitychange"`）のたびに `FUNCTION` を呼びます。`FUNCTION` は `(:type :key :width :height :x :y :visibility)` を受け取ります。イベントの種類とキー、`innerWidth`/`innerHeight`、`scrollX`/`scrollY`、そして `"visible"` または `"hidden"` です。`OPTIONS`: `:keys LIST`（これらのキーだけ）、`:prevent t`（`:keys` を通ったイベントに `preventDefault`）、`:throttle MS`（`MS` ごとに多くても1回の呼び出し。連続したイベントの最後のものは残ります）。`react-cancel` で外します。

```elisp
(react-define-component 'Shortcuts
  :initial-state (lambda (_props) (list :listener nil :pressed nil))
  :did-mount (lambda (self)
               (react-set-state self :listener
                 (react-listen-page 'document "keydown"
                                    (lambda (event) (react-set-state self :pressed (plist-get event :key)))
                                    :keys '("/" "Escape") :prevent t)))
  :will-unmount (lambda (self) (react-cancel (react-state self :listener)))
  :render (lambda (self) (format "%s" (or (react-state self :pressed) "-"))))
(react-testing-render (jsx (Shortcuts)))
(react-testing-answer "page-listen" '(:type "keydown" :key "/"))
(react-testing-html)
;; => "/"
```

<a id="react-media-query"></a>
#### react-media-query

`(react-media-query QUERY FUNCTION)` → リクエスト

CSS のメディアクエリ `QUERY`（`"(prefers-color-scheme: dark)"`、`"(max-width: 600px)"`）が合うかどうかを、`t` か nil で `FUNCTION` に渡して呼びます。ページが答えたらすぐと、変わるたびに呼びます。`react-cancel` で止めます。

<a id="locale-and-intl"></a>
### ロケールと Intl

ページの Emacs は C ロケールで動きます。`format-time-string` は英語の名前を書き、`string-collate-lessp` はコードポイントを比べ、タイムゾーンは指定しない限り UTC です。閲覧者のロケールはブラウザが知っているので、Lisp はブラウザに尋ねます。

<a id="react-locale"></a>
#### react-locale

`(react-locale &optional PART)` → `(:languages ["ja" "en-US"] :timeZone "Asia/Tokyo" :offset 540)`、または1つの `PART`

起動時から分かっています。`:offset` は UTC から東へのずれを分で表したものです。

<a id="react-intl"></a>
#### react-intl

`(react-intl ITEMS FUNCTION &optional LOCALE)` → リクエスト

ブラウザの `Intl` に `ITEMS` を書かせ、そのテキストを同じ順のリストにして `FUNCTION` に渡して呼びます。`LOCALE`（文字列）の既定は閲覧者の言語です。項目は plist で、`:options` は `Intl` のコンストラクタのオプションです:

| 項目 | テキスト |
|---|---|
| `(:type number :value 1234567 :options (:notation "compact"))` | 日本語なら `"123万"` |
| `(:type date :value MILLISECONDS-OR-ISO-STRING :options (:dateStyle "medium"))` | 日付 |
| `(:type relative :value -3 :unit "day")` | `"3 日前"` |
| `(:type plural :value 2)` | 複数形の種類。`"other"` |
| `(:type list :value ("a" "b"))` | `"a、b"` |
| `(:type sort :value ("b" "a"))` | ロケールに合わせて並べ替えた文字列のリスト |

テキストは後で届くので、state に入れておきます。未知の `:type` はホストのエラーになります。

<a id="react-intl-async"></a>
#### react-intl-async

`(react-intl-async ITEMS &optional LOCALE)` → 値がテキストのリストである awaitable

<a id="calling-page-javascript"></a>
### ページの JavaScript を呼ぶ

ホストがしないことは、ページ自身のスクリプトでできます。Lisp はページが登録したコマンドを呼び、ページは Lisp の関数を呼びます。

```html
<script>
  window.elispReactCommands = {
    // (react-host-call "width" (react-node-id (react-ref self "box")) FUNCTION)
    width(id, { reply, node }) { reply(node(id).getBoundingClientRect().width); },
    // (react-host-call "confirm" "Delete it?" FUNCTION)
    confirm(text, { reply }) { reply(window.confirm(text)); },
    // (react-host-tell "log" "text"): a notice gets (ARGUMENT, { node })
    log(text) { console.log(text); },
  };
  // A Lisp function the script calls; the promise resolves when the page is updated.
  document.addEventListener("elisp-react:ready", () => window.elispReact.send("my-app-resized", innerWidth));
</script>
```

コマンドは `(ARGUMENT, { reply, fail, node }) => CANCEL` です。`reply(VALUE)` は Lisp に答えます（Lisp がリクエストを保持していれば何度でも）。`fail(MESSAGE)` は失敗として答え、リクエストを終えます。`node(ID)` は、Lisp が `ID` で知っている DOM ノードです。コマンドが返す関数は `react-cancel` で呼ばれます。ホスト自身のコマンドが優先されます: `timeout`、`interval`、`fetch`、`page-listen`、`measure`、`intl`、`media`、`observe-visible`、`websocket`、`event-source`。通知は `navigate`、`history-go`、`title`、`meta`、`websocket-send`、`storage-set`、`storage-remove` です。対象になるのはオブジェクト自身のプロパティだけです。どちらでもないコマンドはホストのエラーになります。

<a id="react-host-call"></a>
#### react-host-call

`(react-host-call COMMAND ARGUMENT &optional FUNCTION KEEP)` → リクエスト

`ARGUMENT`（JSON のデータ）で `COMMAND`（文字列）を行うよう、ホストに頼みます。ホストが答えると、`OK`（成功なら non-nil）と `VALUE` を渡して `FUNCTION` が呼ばれます。`KEEP` があれば、`FUNCTION` は `react-cancel` まで残り、その後の答えも受け取ります。`FUNCTION` がなければ答えは無視されます。上にあるタイマー、fetch、ページの関数は、これを土台にしています。

```elisp
(defun my-confirm-async (text)
  "An awaitable whose value is t when the visitor confirms TEXT."
  (lambda (resolve reject)
    (react-host-call "confirm" text
                     (lambda (ok value) (if ok (funcall resolve value) (funcall reject value))))))
(defvar my-confirmed 'unknown)
(react-async (setq my-confirmed (react-await (my-confirm-async "Delete it?"))))
(react-testing-flush)
(react-testing-answer "confirm" t)
;; => "Delete it?"
my-confirmed
;; => t
```

<a id="react-host-tell"></a>
#### react-host-tell

`(react-host-tell COMMAND ARGUMENT)` → nil

ホスト、またはページのコマンドに、`ARGUMENT` で `COMMAND` を行うよう伝えます。答えはありません。通知が投げたエラーはコンソールの警告になります。

**ページから Lisp へ**: `window.elispReact.send(NAME, ...ARGS)` は、JSON から変換した `ARGS`（配列はベクタ、オブジェクトは plist）を渡して、Lisp の関数 `NAME`（文字列。intern されます）を [`react-page-call`](#react-page-call) を通して呼び、それから描画します。関数の値は返されません。

```elisp
(defvar my-width nil)
(defun my-app-resized (width) (setq my-width width))
(react-page-call "my-app-resized" [640])
;; => []
my-width
;; => 640
```

<a id="async"></a>
## 非同期処理

Lisp は待てません。ホストからの呼び出しは最後まで実行されます。それでも `react-async` を使えば、待つコードを上から下へ順に書けます。Emacs の `generator.el` の上に作ってあり、本体は状態機械になります。状態機械は `react-await` のたびに止まってページに戻り、ページが答えると続きを実行します。

**awaitable** は、`RESOLVE` と `REJECT` の2つの引数を取る関数です。何かを始め、そのどちらか一方だけを1回だけ、すぐに、または後で呼びます: `(funcall RESOLVE VALUE)` または `(funcall REJECT MESSAGE)`。その戻り値が意味を持つのは取り消しのときだけです。戻り値がリクエスト（`react-host-call` と、それを土台にした関数が返す整数）なら、`react-task-cancel` がそれを取り消します。タスクは、awaitable を受け付けるところならどこでも受け付けられます。ただし `react-query` は除きます。

<a id="react-async"></a>
#### react-async

`(react-async BODY...)` → タスク

`BODY` をすぐに実行します。実行は、awaitable がすぐには答えない最初の `react-await` まで進み、残りはページが答えたときに実行されます。タスクの値は `BODY` の最後の値です。

- `react-await` は `let`、`if`、`when`、`cond`、`pcase`、`progn`、`while`、`dolist`、`dotimes`、`condition-case`、`ignore-errors` の中に置けます。`lambda`、`function`、`closure`、`with-temp-buffer`、`with-current-buffer`、`save-excursion`、`save-current-buffer`、`save-restriction`、`save-match-data`、`mapcar`、`mapc`、`mapcan`、`mapconcat`、`seq-doseq`、`seq-do`、`seq-map`、`maphash`、`cl-loop`、`unwind-protect`（本体でも後始末でも）の中には置けません。置くと、`react-async` は展開されるときにエラーを通知します。ページでは、それはファイルがコンパイルされるときです。
- await するループの中で作ったクロージャは、ループ変数をほかの周回のクロージャと共有します。中で束縛し直してください: `(let ((item item)) (lambda () item))`。
- await の間に state が変わっている可能性があります。await のあとで読み直してください。
- `BODY` の中で捕まえられなかったエラーは、タスクを失敗させます（タスクの値はエラーのメッセージです）。そのタスクを await している側は `react-async-error` を受け取ります。誰も await していないとき、エラーはそのまま伝わります。最初の待ちより前なら `react-async` 自身の外へ、待ちのあとならページへ（赤い枠）伝わります。

<a id="react-await"></a>
#### react-await

`(react-await AWAITABLE)` → `AWAITABLE` が resolve した値

`react-async` の中でだけ使えます（ほかの場所では `iter-yield used outside a generator`）。`AWAITABLE` は `(RESOLVE REJECT)` の関数、またはタスクです。それが reject すると、`react-await` はメッセージをデータとして `react-async-error` を通知します: `(react-async-error MESSAGE)`。したがって `(cadr err)` がメッセージです。

<a id="react-sleep"></a>
#### react-sleep

`(react-sleep MILLISECONDS)` → 値が nil の awaitable

<a id="react-fetch-async"></a>
#### react-fetch-async

`(react-fetch-async URL &rest OPTIONS)` → 値がレスポンスである awaitable

`OPTIONS` は、`:then` と `:catch` を除いて `react-fetch` と同じです。HTTP のエラーステータスもレスポンスです（`:ok` を確かめてください）。レスポンスがまったくないときは reject するので、await はブラウザのメッセージを付けて `react-async-error` を通知します。

<a id="react-all"></a>
#### react-all

`(react-all AWAITABLES)` → awaitable

値は、`AWAITABLES`（awaitable またはタスクのリスト）の値を順に並べたリストで、すべてが答えた時点で得られます。空のリストなら、すぐに nil です。1つでも失敗すると、その時点で失敗します。

<a id="react-race"></a>
#### react-race

`(react-race AWAITABLES)` → awaitable

`AWAITABLES` のうち最初に答えたものと同じように答えます。値でも失敗でも同じです。

<a id="react-task-cancel"></a>
#### react-task-cancel

`(react-task-cancel TASK)` → nil

実行中のタスクを止めます。待っているリクエストは取り消され、本体はそれ以上進まず、状態は `cancelled` になり、そのタスクを await している側はメッセージ `"cancelled"` の `react-async-error` を受け取ります。終わったタスクには何もしません。制限: 2つの await の間の Lisp は、常に次の await まで実行されます（呼び出しが中断されることはありません）。`react-all` と `react-race` の中のリクエストは取り消されません（その答えは無視されます）。

<a id="react-task"></a>
#### react-task

`react-async` が返す構造体です。アクセサ: `react-task-state`（実行中は nil、その後 `done`、`failed`、`cancelled` のどれか）、`react-task-value`（本体の値、または失敗のメッセージ）、`react-task-request`（待っているリクエスト、または nil）、`react-task-iterator` と `react-task-waiting`（内部用）。述語: `react-task-p`。

<a id="react-async-error"></a>
#### react-async-error

処理が失敗した `react-await` で通知されるエラーシンボル（メッセージは `"Asynchronous operation failed"`）です。データは `(MESSAGE)` です。

<a id="async-examples"></a>
### 非同期処理の例

```elisp
(defvar async-log nil)
(react-async
  (push 'start async-log)
  (dotimes (i 2)
    (react-await (react-sleep 100))
    (push (list 'tick i) async-log))
  (condition-case err
      (react-await (react-fetch-async "/down"))
    (react-async-error (push (cadr err) async-log))))
(reverse async-log)
;; => (start)
(react-testing-flush)
(react-testing-time-passes)
(react-testing-time-passes)
(react-testing-answer "fetch" "Failed to fetch" :fail)
;; => (:url "/down" :method "GET" :headers nil :body nil)
(reverse async-log)
;; => (start (tick 0) (tick 1) "Failed to fetch")
```

タスクは組み合わせられます。ある本体が別のタスクを await でき、`react-all` は複数を待ちます。

```elisp
(defvar all-values nil)
(let ((a (react-async (react-await (react-sleep 10)) 'a))
      (b (react-async (react-await (react-sleep 20)) 'b)))
  (react-async (setq all-values (react-await (react-all (list a b (lambda (resolve _reject) (funcall resolve 3))))))))
(react-testing-flush)
(react-testing-time-passes)
all-values
;; => (a b 3)
```

コンポーネントは、自分が外されたとき、または読み込む対象が変わったときに、エフェクトでタスクを止めます:

```elisp
(react-define-component 'Note
  :initial-state (lambda (_props) (list :text nil))
  :render
  (lambda (self)
    (react-effect self 'load (react-props self :id)
      (lambda ()
        (let ((task (react-async
                      (let ((response (react-await (react-fetch-async
                                                    (format "/notes/%s" (react-props self :id))))))
                        (react-set-state self :text (plist-get response :text))))))
          (lambda () (react-task-cancel task)))))
    (or (react-state self :text) "…")))
(react-testing-render (jsx (Note (:id 1))))
(react-unmount "#app")
(react-testing-flush)
react-testing-requests
;; => nil
```

<a id="testing"></a>
## テスト

`lisp/react-testing.el` は、ERT のための、Lisp のデータでできたページです。`react-flush` が返す操作をホストと同じように適用し、ツリー、属性、プロパティ、リスナー（`react-handler` のオプション付き）、そして Lisp がページに求めたことを保持します。テストは描画し、要素を探し、クリックして入力し、リクエストに答え、結果を見ます。どの Emacs でも動きます。ページ自身の Emacs 30.2 では、wasmacs の `tools/scripts/ert.mjs` を使って Node の下で動きます。

```sh
emacs --batch -Q -L path/to/elisp-react/lisp -L . -l app-test.el -f ert-run-tests-batch-and-exit
```

`-L .` はアプリケーションのディレクトリを `load-path` に加えます。`react-testing-load` と `load` は、相対ファイル名をカレントディレクトリではなくそこで探します。ノードの id は Lisp が選んだ番号です（イベントの `:target`）。ブラウザとの違い: 既定の動作はなく、`preventDefault` もなく、FormData の規則もなく（`react-testing-submit` を参照）、レイアウトもありません。また、`react-navigate` は何も変えません（`react-testing-told` に記録されるだけです）。

<a id="react-testing-render"></a>
#### react-testing-render

`(react-testing-render ELEMENT &optional SELECTOR)` → ルートのインスタンス、または nil

最初からやり直し（`react-testing-reset`）、`ELEMENT` を `SELECTOR`（既定は `"#app"`）にマウントして、操作を適用します。`ELEMENT` がコンポーネントなら、ルートのコンポーネントのインスタンスを返します。

<a id="react-testing-load"></a>
#### react-testing-load

`(react-testing-load FILE)` → nil

最初からやり直して、自分でマウントするアプリケーションである `FILE` を読み込み、操作を適用します。`FILE` は `load` と同じ方法で探します。

<a id="react-testing-reset"></a>
#### react-testing-reset

`(react-testing-reset)` → nil

両側のすべてを忘れます（`react-reset` と偽のページ）。アドレスは `http://localhost/`（`:pathname "/"`）、ロケールは `(:languages ["en"] :timeZone "UTC" :offset 0)` になります。

<a id="react-testing-flush"></a>
#### react-testing-flush

`(react-testing-flush)` → nil

Lisp が保留している操作（`react-flush`）を偽のページに適用します。`react-mount`、`load`、直接の `react-set-state` のあとに必要です。何かを行うほかの `react-testing-` 関数は、自分の操作を自分で適用します。

<a id="react-testing-storage"></a>
#### react-testing-storage

`(react-testing-storage KEY VALUE)` → nil

以前の訪問で保存されたかのように、ページのストレージに `KEY` で `VALUE` を持たせます。`react-testing-render` と `react-testing-load` はストレージをリセットするので、順序は `react-testing-reset`、`react-testing-storage`、次に `react-mount` か `load`、最後に `react-testing-flush` です。

<a id="react-testing-location"></a>
#### react-testing-location

`(react-testing-location HREF)` → nil

`HREF` をアドレスにして Lisp に伝え（アドレスのウォッチャーが実行されます）、操作を適用します。`:search` と `:hash` は `HREF` から取ります。`:pathname` は常に `"/"` です。

<a id="react-testing-find-all"></a>
#### react-testing-find-all

`(react-testing-find-all &key TAG CLASS TEXT ATTRIBUTE SELECTOR)` → ノード id のリスト

与えたすべての条件に合う要素を、文書の順に返します: `TAG`（シンボルか文字列）、`CLASS`（そのクラスの1つ）、`TEXT`（子を含むテキスト全体）、`ATTRIBUTE`（`(NAME VALUE)`。どちらも文字列）。`SELECTOR` は探す範囲を1つのルートに限ります。

<a id="react-testing-find"></a>
#### react-testing-find

`(react-testing-find &key TAG CLASS TEXT ATTRIBUTE SELECTOR)` → ノード id

最初に合う要素です。ないときは `react-testing: no element matches ...` を通知します。

<a id="react-testing-text"></a>
#### react-testing-text

`(react-testing-text ID)` → 文字列

ノード `ID` とその中のすべてのテキストです。`:inner-html` を持つ要素では、与えられたままの HTML です。

<a id="react-testing-attribute"></a>
#### react-testing-attribute

`(react-testing-attribute ID NAME)` → 文字列、または nil

ノード `ID` の属性 `NAME`（文字列）です。`t` で設定したものは `""`、ないときは nil です。

<a id="react-testing-property"></a>
#### react-testing-property

`(react-testing-property ID NAME)` → 値

Lisp がノード `ID` に設定した、または `react-testing-input` が入力した DOM プロパティ `NAME`（`"value"`、`"checked"`、または `react-set-property` のもの）です。`"checked"` は `t` か nil です。

<a id="react-testing-html"></a>
#### react-testing-html

`(react-testing-html &optional SELECTOR)` → 文字列、または nil

`SELECTOR`（既定は `"#app"`）の偽のページを HTML にしたもので、ざっと見るためのものです。テキストはエスケープされず、すべての要素に終了タグがあり、属性は最後に設定された順に並びます。

<a id="react-testing-dispatch"></a>
#### react-testing-dispatch

`(react-testing-dispatch ID NAME &optional EVENT)` → nil

ノード `ID` で、plist `EVENT`（`:type NAME :target ID` が加えられます）を持つイベント `NAME` を起こします。イベントはブラウザと同じようにノードとその親をたどって上がり、その名前のリスナーをそれぞれ実行します。その際、`react-handler` のオプション `:self`、`:keys`、`:stop` に従います。ヘルパーのないイベントに使います: `(react-testing-dispatch id "change" '(:checked t))`。

<a id="react-testing-click"></a>
#### react-testing-click

`(react-testing-click ID)` → nil

ほかのデータのない `click` イベントです。

<a id="react-testing-input"></a>
#### react-testing-input

`(react-testing-input ID VALUE)` → nil

入力欄 `ID` に `VALUE` を入力します。`value` プロパティを設定し、続いて `:value VALUE` を持つ `input` イベントと `change` イベントを起こします。

<a id="react-testing-key"></a>
#### react-testing-key

`(react-testing-key ID KEY)` → nil

`:key KEY`（`"Enter"`、`"a"`）を持つ `keydown` イベントです。

<a id="react-testing-submit"></a>
#### react-testing-submit

`(react-testing-submit ID)` → nil

フォーム `ID` での `submit` イベントです。`:form` は、フォームの中で `name` 属性を持つすべての要素から作ります。値は `value` プロパティ、なければ `value` 属性、それもなければ `""` です。ブラウザと違い、チェックされていないチェックボックスと、名前のあるすべてのボタンも含めます。

<a id="react-testing-answer"></a>
#### react-testing-answer

`(react-testing-answer COMMAND VALUE &optional OK)` → リクエストの引数

`COMMAND`（`"fetch"`、`"timeout"`、`"page-listen"`、ページのコマンド）の、待っているうちで最も古いリクエストに `VALUE` で答え、操作を適用します。`OK` が `:fail` でなければ成功として答えます。待っているものがないときは `react-testing: nothing waits for COMMAND` を通知します。リクエストはこの答えで `react-testing-requests` から外れます。保持されるもの（ページのリスナー、メディアクエリ、接続）も同じで、テスト用のキットはそれに1回だけ答えます。インターバルは `react-testing-time-passes` によって何度でも発火します。

<a id="react-testing-answer-fetch"></a>
#### react-testing-answer-fetch

`(react-testing-answer-fetch STATUS TEXT)` → fetch の引数、`(:url ... :method ...)`

待っているうちで最も古い fetch に、レスポンス `(:status STATUS :ok (< STATUS 400) :text TEXT :headers nil)` で答えます。

<a id="react-testing-time-passes"></a>
#### react-testing-time-passes

`(react-testing-time-passes)` → nil

いま待っているすべてのタイムアウトを1回ずつ発火させ（そして忘れ）、すべてのインターバルを1回ずつ発火させます。発火したものが始めたタイマーは、次の呼び出しまで待ちます。

<a id="react-testing-requests"></a>
#### react-testing-requests

変数です。Lisp がページに求め、答えを待っているものを古い順に並べたもので、それぞれ `(REQUEST COMMAND ARGUMENT)` です。取り消されたリクエストは取り除かれます。

<a id="react-testing-told"></a>
#### react-testing-told

変数です。Lisp がページに伝えたことを古い順に並べたもので、それぞれ `(COMMAND ARGUMENT)` です: `("storage-set" (:key ... :value ...))`、`("navigate" (:url ... :replace ...))`、`("title" (:text ...))`。

<a id="react-testing-invoked"></a>
#### react-testing-invoked

変数です。ノードに対して呼ばれたメソッドを古い順に並べたもので、それぞれ `(ID METHOD ARGS...)` です。

<a id="rules-and-pitfalls"></a>
## 規則と落とし穴

1. どのファイルも `;;; NAME.el --- ...  -*- lexical-binding: t; -*-` で始めてください。1行目にこのクッキーがないとき、ページはそれを加えますが、ネイティブの Emacs（テスト、サーバー）はそのようなファイルを動的束縛で読み込み、`self` を閉じ込めたクロージャは `void-variable` で失敗します。
2. ネイティブの Emacs では、アプリケーションのファイルをコンパイルする前に `react.el` が読み込まれている必要があります。先頭に `(require 'react)` を置くか、コマンドラインで `-l react` を指定してください。そうしないと、`jsx` と `react-async` は関数呼び出しとしてコンパイルされます。lint として、警告をエラーとしてバイトコンパイルしてください: `emacs --batch -Q -L path/to/lisp -l react --eval '(setq byte-compile-error-on-warn t)' -f batch-byte-compile app.el`。
3. `react-mount` はすぐに描画します。使うコンポーネントは、それまでにすべて定義されていなければなりません。`react-mount` は最後のファイルの最後に置いてください。後のファイルで定義されたコンポーネントは、未知の要素として（メッセージ付きで）描画され、そのままになります。
4. ライブラリのファイルは、それを `require` するファイルより前に並べ、`(provide 'NAME)` で終えてください。順番が来る前に require されたファイルは2回読み込まれ（`require` によってソースから、自分の順番でコンパイル済みのものが）、トップレベルのフォームが2回実行されます。
5. `jsx` の中では、コンポーネントは大文字で始まる名前です。小文字のコンポーネント名は、ただのリストの形でだけ働きます。`jsx` の中では関数呼び出しになります。
6. HTML や SVG のタグと同じ名前のコンポーネント（`label`、`button`、`title`）は、ページのすべての要素でそのタグを置き換えます。
7. `jsx` の中では、タグ名で始まるリストはマークアップです。タグと同じ名前の関数（`mark`、または自分で定義した `label`、`filter`、`search`、`time`、`data`）は、そこでは直接呼べません。値を前もって計算するか、`funcall` を使ってください。
8. すべてのファイルが1つの Emacs を共有します。グローバルな関数名と変数名には、アプリケーションの名前を接頭辞として付けてください。既存の名前の `defun` は、`react.el` も含めたすべてに対して、その定義を置き換えます。
9. 変化するリストの子には、すべて、兄弟の中で一意な `:key` を付けてください。key がないと子は位置で対応付けられ、行のコンポーネントの state は、行ではなく位置に残ります。
10. state をその場で変更しないでください（`setcar`、state の中の plist への `plist-put`、`nconc`、`delete`、state のリストへの `sort`）。新しい値を作ってください: `react-plist-with`、`mapcar`、`seq-remove`、`append`。`:pure`、`:should-update`、`react-changed-p`、コンテキストは、リストを同一性（identity）で比べます。
11. ハンドラでは、描画が取り込んだ値ではなく、イベントが起きたときに state を読んでください: `(react-state self :todos)`。そうしないと、すばやく続いた2つのイベントが、どちらも古い値から始めてしまいます。`react-await` のあとでは、state を読み直してください。
12. イベント名は、`:on-` のあとに DOM のイベントの種類を続けたものです: `:on-keydown`、`:on-dblclick`、`:on-pointerdown`。`:on-key-down` は、決して来ないイベント `key-down` を待ち受けます。
13. Lisp は、既定の動作を後から止めることはできません。前もって宣言してください: `(react-handler f :prevent t)`。フォームの `submit` は常に止められます。フォームの中の `<button>` は、`:type "button"` がなければフォームを送信します。
14. シンボル、キーワード、ベクタは子になりません（`Not an element`）。`(symbol-name x)` や `(format "%s" x)` と書いてください。`react-response-json` から得たベクタは、`(append v nil)` か `mapcar` でリストにしてください。
15. `:value` を付けると、入力欄は制御されたものになります。`:on-input` から state を設定してください。そうしないと、次の描画が古い値を書き戻します。
16. `react-location`、`react-locale`、`react-storage-get` は state ではありません。それらを読むコンポーネントは、値が変わっても再描画されません。それらを監視し（`react-location-watch`、`react-storage-watch`）、state を設定するか `react-force-update` を呼んでください。
17. `:did-mount` やエフェクトで始めたものは、`:will-unmount` やエフェクトの後始末で止めてください: `react-set-interval`、`react-listen-page`、`react-media-query`、`react-observe-visible`、`react-websocket`、`react-event-source`、`react-location-watch`、`react-storage-watch`。そうしないと、それらは、なくなったコンポーネントを呼び続けます。
18. `:render` や `:did-update` の中で `react-set-state` を無条件に呼ばないでください。flush は100回繰り返したあと、`"Components keep changing state while rendering"` を出して諦めます。
19. `react-effect` のキーはシンボルで、コンポーネントの中で一意です。deps は `equal` で比べます。deps が nil なら1回だけ実行します。
20. `react-await` は、generator.el が書き換えられる場所でだけ使えます。`lambda`、`mapcar`、`seq-map`、`cl-loop`、`with-temp-buffer`、`save-excursion`、`unwind-protect` の中では使えません。ループには `dolist`、`dotimes`、`while` を使ってください。
21. ホストからの呼び出しは中断できません。タイムアウト（30秒）を過ぎると、Emacs は完全に止められます。長い処理は、`react-async` の中で `(react-await (react-sleep 0))` を挟んで区切ってください。
22. ページに送るものはすべて JSON です: `react-host-call`、`react-host-tell`、`react-invoke` の引数、`:headers`。キーがキーワードの plist、ベクタ、文字列、数、`t`、`:false`、nil を使ってください。シンボルやただのリスト（`'("a" "b")`）には JSON の形がなく、その呼び出しの答え全体を失敗させます。配列には `vconcat`、シンボルには `symbol-name` を使ってください。
23. `react-invoke` のメソッドと `react-set-property` のプロパティは一覧にあるものだけを、コマンドはホストかページが定義しているものだけを使ってください。未知のメソッドやコマンドがあると、ホストはその答えの残りの操作を捨てます。
24. `react-query` のローダーは、`(react-fetch-async URL)` のような `(RESOLVE REJECT)` の関数を返します。そこに `react-async` のタスクを使うと、描画の中でエラーになります。
25. コンポーネントの要素に付けた `:ref` は、ただの prop です。子が描画する要素に届くには、`(react-make-ref self NAME)` を自分で決めた prop で下に渡し、それをその要素に付けてください。
26. 生のバイトを含む文字列（`json-serialize` の出力、`url-unhex-string`）は UTF-8 としてデコードされます。それでもテキストにならない部分は、メッセージ付きで U+FFFD になります。バイトは `:as 'base64` で fetch してください。
27. ファイルを読み込み直す（ホストの `load`）と、`defvar` の値は残り、`defconst`、`setq`、`defun` は再実行されます。定義し直したコンポーネントは state を保ちます。変更した `:initial-state` が反映されるのは、新しいインスタンスか、ページを読み込み直したあとだけです。
28. テストでは、`react-testing-render` と `react-testing-load` がストレージとアドレスをリセットします。`react-testing-reset` のあとに `react-testing-storage` で設定し、次にマウントするか `load` して、それから `react-testing-flush` してください。
29. ページの中で `react-testing` を `require` しないでください。ページの `load-path` にはありません。テストは、ページが列挙しないファイルに置いてください。
30. 秘密を `localStorage` に置かないでください。オリジンのどのページもそれを読めます。そこに保存されたコンパイル済みのコードも同じです。

<a id="worked-examples"></a>
## 作例

どの作例も、ファイルとテストの組です。テストは[テスト](#testing)にあるコマンドで実行します。

<a id="counter"></a>
### カウンター

```html
<!doctype html>
<html lang="en">
  <head><meta charset="utf-8"><title>Counter</title></head>
  <body>
    <div id="app">Loading Emacs…</div>
    <script type="text/emacs-lisp" src="counter.el"></script>
    <script type="module" src="https://modeverv.github.io/elisp-react/js/elisp-react.js"></script>
  </body>
</html>
```

```elisp
;;; counter.el --- a counter  -*- lexical-binding: t; -*-

(require 'react)

(react-define-component 'Counter
  :initial-state (lambda (props) (list :count (or (plist-get props :start) 0)))
  :render
  (lambda (self)
    (let ((count (react-state self :count)))
      (jsx (div (:class "counter")
             (p (:class "count") (format "Count: %d" count))
             (button (:class "increment"
                      :on-click (lambda (_event)
                                  (react-set-state self :count (1+ (react-state self :count)))))
               "+1")
             (button (:class "reset" :disabled (= count 0)
                      :on-click (lambda (_event) (react-set-state self :count 0)))
               "reset"))))))

(react-mount (jsx (Counter (:start 3))) "#app")
```

```elisp
;;; counter-test.el --- tests of counter.el  -*- lexical-binding: t; -*-

(require 'ert)
(require 'react-testing)

(ert-deftest counter-counts-and-resets ()
  (react-testing-load "counter.el")
  (should (equal (react-testing-text (react-testing-find :class "count")) "Count: 3"))
  (react-testing-click (react-testing-find :class "increment"))
  (should (equal (react-testing-text (react-testing-find :class "count")) "Count: 4"))
  (should-not (react-testing-attribute (react-testing-find :class "reset") "disabled"))
  (react-testing-click (react-testing-find :class "reset"))
  (should (equal (react-testing-text (react-testing-find :class "count")) "Count: 0"))
  (should (equal (react-testing-attribute (react-testing-find :class "reset") "disabled") "")))
```

<a id="todo-list"></a>
### Todo リスト

key 付きのリスト、制御された入力欄、フォームの送信、描画を省く行、そして `localStorage` に保存するリスト。

```elisp
;;; todos.el --- a todo list  -*- lexical-binding: t; -*-

(require 'react)
(require 'seq)
(require 'subr-x)

(defun todos-next-id (todos)
  (1+ (apply #'max 0 (mapcar (lambda (todo) (plist-get todo :id)) todos))))

(react-define-component 'TodoItem
  ;; Renders only when its todo changed; the handlers read the function
  ;; props when the event happens.
  :pure t
  :render
  (lambda (self)
    (let ((todo (react-props self :todo)))
      (jsx (li (:class (if (plist-get todo :done) "todo done" "todo"))
             (input (:type "checkbox" :class "toggle" :checked (plist-get todo :done)
                     :on-change (lambda (_event)
                                  (funcall (react-props self :on-toggle) (plist-get todo :id)))))
             (span (:class "text") (plist-get todo :text))
             (button (:type "button" :class "delete"
                      :on-click (lambda (_event)
                                  (funcall (react-props self :on-delete) (plist-get todo :id))))
               "×"))))))

(react-define-component 'TodoApp
  :initial-state (lambda (_props) (list :todos (react-storage-get "todos" nil) :draft ""))
  :did-update (lambda (self _previous-props previous-state)
                (unless (eq (react-state self :todos) (plist-get previous-state :todos))
                  (react-storage-set "todos" (react-state self :todos))))
  :render
  (lambda (self)
    (let* ((todos (react-state self :todos))
           (toggle-todo
            (lambda (id)
              (react-set-state
               self :todos
               (mapcar (lambda (todo)
                         (if (= (plist-get todo :id) id)
                             (react-plist-with todo :done (not (plist-get todo :done)))
                           todo))
                       (react-state self :todos)))))
           (delete-todo
            (lambda (id)
              (react-set-state
               self :todos
               (seq-remove (lambda (todo) (= (plist-get todo :id) id)) (react-state self :todos)))))
           (add-todo
            (lambda (event)
              (let ((text (string-trim (or (react-form-value event "text") "")))
                    (todos (react-state self :todos)))
                (unless (string-empty-p text)
                  (react-set-state
                   self
                   :todos (append todos (list (list :id (todos-next-id todos) :text text :done nil)))
                   :draft ""))))))
      (jsx (main
             (form (:class "new" :on-submit add-todo)
               (input (:name "text" :class "new-text" :placeholder "What needs to be done?"
                       :value (react-state self :draft)
                       :on-input (lambda (event) (react-set-state self :draft (plist-get event :value)))))
               (button (:class "add" :disabled (string-empty-p (string-trim (react-state self :draft))))
                 "add"))
             (ul (:class "todos")
               (mapcar (lambda (todo)
                         (jsx (TodoItem (:key (plist-get todo :id) :todo todo
                                         :on-toggle toggle-todo :on-delete delete-todo))))
                       todos))
             (p (:class "left")
               (format "%d left" (seq-count (lambda (todo) (not (plist-get todo :done))) todos))))))))

(react-mount (jsx (TodoApp)) "#app")
```

<a id="loading-data"></a>
### データの読み込み

読み込み中の状態、エラーの状態、再試行を持つ `react-async` です。`quotes.json` は `{"id": ..., "text": ...}` の配列です。

```elisp
;;; quotes.el --- loading data with react-async  -*- lexical-binding: t; -*-

(require 'react)

(defun quotes-load (self)
  "Load the quotes into SELF's state: loading, then loaded or failed."
  (react-async
    (react-set-state self :status 'loading :error nil)
    (condition-case failure
        (let ((response (react-await (react-fetch-async "quotes.json"))))
          (if (plist-get response :ok)
              (react-set-state self :status 'loaded
                               :quotes (append (react-response-json response) nil))
            (react-set-state self :status 'failed
                             :error (format "HTTP %d" (plist-get response :status)))))
      ;; No response at all: offline, refused.
      (react-async-error (react-set-state self :status 'failed :error (cadr failure))))))

(react-define-component 'Quotes
  :initial-state (lambda (_props) (list :status 'loading :quotes nil :error nil))
  :did-mount (lambda (self) (quotes-load self))
  :render
  (lambda (self)
    (pcase (react-state self :status)
      ('loading (jsx (p (:class "status") "Loading…")))
      ('failed (jsx (div (p (:class "error") (react-state self :error))
                         (button (:class "retry" :on-click (lambda (_event) (quotes-load self)))
                           "retry"))))
      (_ (jsx (ul (:class "quotes")
                (mapcar (lambda (item) (jsx (li (:key (plist-get item :id)) (plist-get item :text))))
                        (react-state self :quotes))))))))

(react-mount (jsx (Quotes)) "#app")
```

```elisp
;;; quotes-test.el --- tests of quotes.el  -*- lexical-binding: t; -*-

(require 'ert)
(require 'react-testing)

(ert-deftest quotes-load-fail-retry ()
  (react-testing-load "quotes.el")
  (should (equal (react-testing-text (react-testing-find :class "status")) "Loading…"))
  ;; No response at all.
  (should (equal (plist-get (react-testing-answer "fetch" "Failed to fetch" :fail) :url) "quotes.json"))
  (should (equal (react-testing-text (react-testing-find :class "error")) "Failed to fetch"))
  ;; Retry: an HTTP error, then data.
  (react-testing-click (react-testing-find :class "retry"))
  (react-testing-answer-fetch 500 "")
  (should (equal (react-testing-text (react-testing-find :class "error")) "HTTP 500"))
  (react-testing-click (react-testing-find :class "retry"))
  (react-testing-answer-fetch 200 "[{\"id\":1,\"text\":\"Simple things should be simple.\"}]")
  (should (equal (mapcar #'react-testing-text (react-testing-find-all :tag 'li))
                 '("Simple things should be simple."))))
```

<a id="theme-from-a-context"></a>
### コンテキストから得るテーマ

最上位で提供したテーマを、描画を省く `:pure` コンポーネントを通して、2階層下で読みます。

```elisp
;;; theme.el --- context  -*- lexical-binding: t; -*-

(require 'react)

(react-define-component 'ThemedButton
  :render
  (lambda (self)
    (jsx (button (:class (list "button" (react-context self 'theme "light")))
           (react-props self :label)))))

(react-define-component 'Toolbar
  :pure t
  :render (lambda (_self) (jsx (nav (ThemedButton (:label "Save")) (ThemedButton (:label "Load"))))))

(react-define-component 'ThemeApp
  :initial-state (lambda (_props) (list :theme "light"))
  :render
  (lambda (self)
    (jsx (div
           (button (:class "switch"
                    :on-click (lambda (_event)
                                (react-set-state self :theme (if (equal (react-state self :theme) "light")
                                                                 "dark"
                                                               "light"))))
             "switch theme")
           (react-provide 'theme (react-state self :theme) (jsx (Toolbar)))))))

(react-mount (jsx (ThemeApp)) "#app")
```

```elisp
;;; theme-test.el --- tests of theme.el  -*- lexical-binding: t; -*-

(require 'ert)
(require 'react-testing)

(ert-deftest theme-reaches-buttons-below-a-pure-component ()
  (react-testing-load "theme.el")
  (should (equal (length (react-testing-find-all :class "light")) 2))
  (react-testing-click (react-testing-find :class "switch"))
  (should (equal (length (react-testing-find-all :class "dark")) 2))
  (should (equal (react-testing-attribute (react-testing-find :text "Save") "class") "button dark")))
```

<a id="a-test-with-react-testingel"></a>
### react-testing.el によるテスト

上の Todo リストのテストです: 最初に保存されているデータ、入力と送信、DOM ノードを保つ key、チェックボックス、そしてページに保存するよう伝えた内容。

```elisp
;;; todos-test.el --- tests of todos.el  -*- lexical-binding: t; -*-

(require 'ert)
(require 'react-testing)

(defun todos-test-texts ()
  (mapcar #'react-testing-text (react-testing-find-all :class "text")))

(ert-deftest todos-add-delete-toggle ()
  ;; Not react-testing-load: it would reset the storage set here.
  (react-testing-reset)
  (react-testing-storage "todos" '((:id 1 :text "Write tests" :done nil)))
  (load "todos.el" nil t)
  (react-testing-flush)
  (should (equal (todos-test-texts) '("Write tests")))
  (should (react-testing-attribute (react-testing-find :class "add") "disabled"))
  ;; Type, then submit the form.
  (react-testing-input (react-testing-find :class "new-text") "Run them")
  (should-not (react-testing-attribute (react-testing-find :class "add") "disabled"))
  (react-testing-submit (react-testing-find :tag 'form :class "new"))
  (should (equal (todos-test-texts) '("Write tests" "Run them")))
  (should (equal (react-testing-property (react-testing-find :class "new-text") "value") ""))
  ;; Keys: the second row keeps its DOM node when the first goes.
  (let ((second-row (cadr (react-testing-find-all :tag 'li))))
    (react-testing-click (car (react-testing-find-all :class "delete")))
    (should (equal (react-testing-find-all :tag 'li) (list second-row))))
  ;; A checkbox: a change event.
  (react-testing-dispatch (react-testing-find :class "toggle") "change" '(:checked t))
  (should (equal (react-testing-text (react-testing-find :class "left")) "0 left"))
  (should (equal (react-testing-attribute (react-testing-find :tag 'li) "class") "todo done"))
  ;; The page was told to store the list.
  (let ((stored (car (last react-testing-told))))
    (should (equal (car stored) "storage-set"))
    (should (equal (read (plist-get (cadr stored) :value))
                   '((:id 2 :text "Run them" :done t))))))
```
