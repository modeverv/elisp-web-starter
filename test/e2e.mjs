// SPDX-License-Identifier: 0BSD  (yours to change; no conditions)
// The application in a real browser: headless Chrome, the page's Emacs as
// WebAssembly, run.sh's server behind it.
//
//   npm run test:e2e        (node test/e2e.mjs)
//
// It copies the project to a temporary directory (so that its .data/ is
// not yours), starts ./run.sh there on a free port and goes through the
// application: write, refuse, mark done, reload, read, change, delete, a
// missing note, the about page, an address that is no page.
//
// Needs Node 24 or later, Chrome (CHROME_PATH, else the usual places), a
// native Emacs (as run.sh), and the internet for the page's Emacs, unless
// ./fetch-emacs.sh has put the pinned one into vendor/wasmacs/: then that
// one is used, and the test says which.
import { spawn, spawnSync } from "node:child_process";
import { existsSync } from "node:fs";
import { cp, mkdtemp, rm } from "node:fs/promises";
import { createServer } from "node:net";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { fileURLToPath } from "node:url";
import { CdpClient, devToolsUrl, evaluate, waitUntil } from "./lib/cdp.mjs";

const root = fileURLToPath(new URL("..", import.meta.url));
const pass = (message) => console.log(`PASS ${message}`);

function findChrome() {
  if (process.env.CHROME_PATH) return process.env.CHROME_PATH;
  const mac = "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome";
  if (existsSync(mac)) return mac;
  for (const name of ["google-chrome", "google-chrome-stable", "chromium", "chromium-browser"]) {
    const found = spawnSync("sh", ["-c", `command -v ${name}`], { encoding: "utf8" }).stdout.trim();
    if (found) return found;
  }
  throw new Error("no Chrome found: set CHROME_PATH");
}

const freePort = () => new Promise((resolve) => {
  const server = createServer();
  server.listen(0, "127.0.0.1", () => { const { port } = server.address(); server.close(() => resolve(port)); });
});

const work = await mkdtemp(join(tmpdir(), "elisp-web-starter-e2e-"));
const project = join(work, "project");
let server = null, chrome = null, client = null;
try {
  await cp(root, project, {
    recursive: true,
    filter: (source) => !/[/\\](\.git|\.data|\.cache|node_modules)$/.test(source),
  });
  const port = await freePort();
  const origin = `http://127.0.0.1:${port}`;
  let log = "";
  server = spawn(join(project, "run.sh"), [String(port)], { stdio: ["ignore", "pipe", "pipe"] });
  server.stdout.on("data", (chunk) => { log += chunk; });
  server.stderr.on("data", (chunk) => { log += chunk; });
  await waitUntil(() => fetch(`${origin}/api/health`).then((response) => response.ok, () => false), "run.sh's server", 30_000)
    .catch((error) => { throw new Error(`${error.message}\n${log}`); });
  const health = await (await fetch(`${origin}/api/health`)).text();
  pass(`run.sh answers: ${health.slice(0, 60)}...`);

  chrome = spawn(findChrome(), [
    "--headless=new", "--disable-gpu", "--no-first-run", "--no-default-browser-check", "--window-size=1200,900",
    "--remote-debugging-port=0", `--user-data-dir=${join(work, "profile")}`, "about:blank",
  ], { stdio: ["ignore", "ignore", "pipe"] });
  client = new CdpClient(await devToolsUrl(chrome));
  const { targetId } = await client.send("Target.createTarget", { url: "about:blank" });
  const { sessionId } = await client.send("Target.attachToTarget", { targetId, flatten: true });
  await client.send("Page.enable", {}, sessionId);
  await client.send("Runtime.enable", {}, sessionId);
  const failures = [];
  client.onEvent = (message) => {
    if (message.method === "Runtime.exceptionThrown") failures.push(message.params.exceptionDetails.exception?.description);
  };
  const js = (expression) => evaluate(client, sessionId, expression);
  const until = (expression, label, timeout = 30_000) =>
    waitUntil(() => js(`Boolean(${expression})`).catch(() => false), label, timeout);
  const texts = (selector) => js(`[...document.querySelectorAll(${JSON.stringify(selector)})].map((node) => node.textContent)`);
  const type = (selector, value) => js(`(() => {
    const field = document.querySelector(${JSON.stringify(selector)});
    field.value = ${JSON.stringify(value)};
    field.dispatchEvent(new Event("input", { bubbles: true }));
    return true;
  })()`);
  const click = (selector) => js(`(document.querySelector(${JSON.stringify(selector)}).click(), true)`);
  const submit = (selector) => js(`(document.querySelector(${JSON.stringify(selector)}).requestSubmit(), true)`);
  const go = (hash) => js(`(location.hash = ${JSON.stringify(hash)}, true)`);

  await client.send("Page.navigate", { url: `${origin}/` }, sessionId);
  // The first visit downloads Emacs (about 5 MB) unless the browser has it.
  await until("document.querySelector('.home .empty')", "the empty list (Emacs started in the page)", 180_000);
  const runtime = await js(`document.querySelector('meta[name="elisp-react:wasmacs"]')?.content || "https://modeverv.github.io/wasmacs/"`);
  pass(`the page's Emacs runs (from ${runtime}): ${JSON.stringify(await texts(".empty"))}`);

  await type("input.title", "Milk");
  await type("textarea.body", "2 litres\nskimmed");
  await submit("form.note-form");
  await until("[...document.querySelectorAll('li.note .title')].some((node) => node.textContent === 'Milk')", "the new note in the list");
  if (await js("document.querySelector('input.title').value") !== "") throw new Error("the form was not emptied");
  pass("a note is written: POST /api/notes, the list loads again");

  await submit("form.note-form");
  await until("document.querySelector('.note-form .problem')?.textContent === 'A note needs a title'", "a note without a title refused");
  pass("a note without a title is refused in the page (the check of shared/)");

  await click("li.note .toggle");
  await until("document.querySelector('li.note.done')", "the note marked done");
  pass("marked done from the list: PUT /api/notes/ID");

  await client.send("Page.reload", {}, sessionId);
  await until("document.querySelector('li.note.done .title')?.textContent === 'Milk'", "the note after a reload", 120_000);
  pass("after a reload the server still has it");

  await click("li.note .title");
  await until("document.querySelector('.note-page h1')?.textContent === 'Milk'", "the note's page");
  await until("document.title === 'Milk · Notes'", "the note's title in the document's");
  if (await js("document.querySelector('.note-page .text').textContent") !== "2 litres\nskimmed") throw new Error("the text differs");
  pass(`its page: ${JSON.stringify(await js("location.hash"))}, title ${JSON.stringify(await js("document.title"))}`);

  await click("button.edit");
  await until("document.querySelector('.note-page input.title')?.value === 'Milk'", "the form with the note");
  await type(".note-page input.title", "Oat milk");
  await submit(".note-page form.note-form");
  await until("document.querySelector('.note-page h1')?.textContent === 'Oat milk'", "the changed note");
  pass("changed: PUT /api/notes/ID");

  await click("button.delete");
  await until("document.querySelector('.confirm')", "the question");
  await click("button.really-delete");
  await until("location.hash === '#/' && document.querySelector('.home .empty')", "the empty list after the delete");
  pass("deleted, asked once more first; the list is shown again");

  await go("#/notes/1");
  await until("document.querySelector('.failed')?.textContent.includes('No such note')", "the missing note");
  pass("a missing note: the server's 404 on the page, with Try again");

  await go("#/about");
  await until("document.querySelector('.about .server-emacs')", "the about page");
  pass(`about: ${JSON.stringify(await texts(".facts dd"))}`);

  await go("#/nowhere");
  await until("document.querySelector('.missing')?.textContent.includes('/nowhere')", "the 404 page");
  pass("an address that is no page: pages/404.el");

  const refused = await js(`fetch("api/notes", { method: "POST", body: "(:title 3)" }).then(async (r) => [r.status, await r.text()])`);
  if (refused[0] !== 400) throw new Error(`a wrong body got ${refused}`);
  pass(`the server checks the body too: ${JSON.stringify(refused)}`);

  if (failures.length) throw new Error(`errors in the page: ${failures.join("\n")}`);
  console.log("e2e passed");
} finally {
  client?.close();
  chrome?.kill("SIGTERM");
  server?.kill("SIGTERM");
  await new Promise((resolve) => setTimeout(resolve, 300));
  await rm(work, { recursive: true, force: true }).catch(() => {});
}
