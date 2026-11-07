import { mkdtempSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { pathToFileURL } from "node:url";

export class FakeNode {
  parentNode: FakeElement | FakeDocumentFragment | null = null;

  get nextSibling(): FakeNode | null {
    const parent = this.parentNode;
    if (!parent) return null;
    const index = parent.childNodes.indexOf(this);
    if (index === -1) return null;
    return parent.childNodes[index + 1] ?? null;
  }

  get isConnected(): boolean {
    let current: FakeNode | null = this;
    while (current) {
      if (current instanceof FakeDocument) return true;
      current = current.parentNode;
    }
    return false;
  }
}

export class FakeTextNode extends FakeNode {
  constructor(public data: string) {
    super();
  }

  get textContent(): string {
    return this.data;
  }
}

export class FakeCommentNode extends FakeNode {
  constructor(public data: string) {
    super();
  }

  get textContent(): string {
    return "";
  }
}

export class FakeDocumentFragment extends FakeNode {
  childNodes: FakeNode[] = [];

  append(node: FakeNode) {
    appendChild(this, node);
  }

  appendChild(node: FakeNode) {
    appendChild(this, node);
    return node;
  }

  insertBefore(node: FakeNode, reference: FakeNode | null) {
    insertBeforeNode(this, node, reference);
  }

  removeChild(node: FakeNode) {
    removeChildNode(this, node);
  }

  get textContent(): string {
    return this.childNodes.map((child) => getTextContent(child)).join("");
  }
}

export class FakeElement extends FakeNode {
  childNodes: FakeNode[] = [];
  attributes = new Map<string, string>();
  listeners = new Map<string, Array<(event: any) => void>>();
  replaceChildrenCalls = 0;
  value = "";
  checked = false;
  disabled = false;
  selected = false;
  id = "";
  className = "";
  type = "";
  style: { cssText: string };

  constructor(public tagName: string) {
    super();
    const element = this;
    this.style = {
      get cssText() {
        return element.attributes.get("style") ?? "";
      },
      set cssText(value: string) {
        element.attributes.set("style", value);
      },
    };
  }

  append(node: FakeNode) {
    appendChild(this, node);
  }

  appendChild(node: FakeNode) {
    appendChild(this, node);
    return node;
  }

  insertBefore(node: FakeNode, reference: FakeNode | null) {
    insertBeforeNode(this, node, reference);
  }

  removeChild(node: FakeNode) {
    removeChildNode(this, node);
  }

  replaceChildren(...nodes: FakeNode[]) {
    this.replaceChildrenCalls += 1;
    this.childNodes = [];
    for (const node of nodes) {
      this.append(node);
    }
  }

  setAttribute(name: string, value: string) {
    this.attributes.set(name, value);
    if (name === "id") this.id = value;
    if (name === "class") this.className = value;
    if (name === "value") this.value = value;
    if (name === "type") this.type = value;
  }

  removeAttribute(name: string) {
    this.attributes.delete(name);
    if (name === "id") this.id = "";
    if (name === "class") this.className = "";
    if (name === "value") this.value = "";
  }

  hasAttribute(name: string): boolean {
    return this.attributes.has(name);
  }

  addEventListener(name: string, handler: (event: any) => void) {
    const handlers = this.listeners.get(name) ?? [];
    handlers.push(handler);
    this.listeners.set(name, handlers);
  }

  dispatchEvent(event: any) {
    const handlers = this.listeners.get(event.type) ?? [];
    event.target = event.target ?? this;
    for (const handler of handlers) {
      handler(event);
    }
  }

  focus() {}
  select() {}

  get textContent(): string {
    return this.childNodes.map((child) => getTextContent(child)).join("");
  }
}

export class FakeDocument extends FakeNode {
  body: FakeElement;
  listeners = new Map<string, Array<(event: any) => void>>();

  constructor() {
    super();
    this.body = new FakeElement("body");
    this.body.parentNode = this;
  }

  createElement(tagName: string) {
    return new FakeElement(tagName);
  }

  createTextNode(data: string) {
    return new FakeTextNode(data);
  }

  createComment(data: string) {
    return new FakeCommentNode(data);
  }

  createDocumentFragment() {
    return new FakeDocumentFragment();
  }

  getElementById(id: string): FakeElement | null {
    return findElement(this.body, (element) => element.id === id);
  }

  addEventListener(name: string, handler: (event: any) => void) {
    const handlers = this.listeners.get(name) ?? [];
    handlers.push(handler);
    this.listeners.set(name, handlers);
  }

  removeEventListener(name: string, handler: (event: any) => void) {
    const handlers = this.listeners.get(name) ?? [];
    this.listeners.set(
      name,
      handlers.filter((candidate) => candidate !== handler),
    );
  }

  dispatchEvent(event: any) {
    const handlers = this.listeners.get(event.type) ?? [];
    for (const handler of handlers) {
      handler(event);
    }
  }
}

function adoptNode(parent: FakeElement | FakeDocumentFragment, node: FakeNode) {
  if (node.parentNode) {
    const currentParent = node.parentNode;
    const currentIndex = currentParent.childNodes.indexOf(node);
    if (currentIndex !== -1) {
      currentParent.childNodes.splice(currentIndex, 1);
    }
  }
  node.parentNode = parent;
}

function appendChild(parent: FakeElement | FakeDocumentFragment, node: FakeNode) {
  if (node instanceof FakeDocumentFragment) {
    const children = [...node.childNodes];
    node.childNodes = [];
    for (const child of children) {
      adoptNode(parent, child);
      parent.childNodes.push(child);
    }
    return;
  }
  adoptNode(parent, node);
  parent.childNodes.push(node);
}

function insertBeforeNode(parent: FakeElement | FakeDocumentFragment, node: FakeNode, reference: FakeNode | null) {
  if (reference === null) {
    appendChild(parent, node);
    return;
  }
  const index = parent.childNodes.indexOf(reference);
  if (index === -1) {
    throw new Error("reference node is not a child of parent");
  }
  if (node instanceof FakeDocumentFragment) {
    const children = [...node.childNodes];
    node.childNodes = [];
    for (const child of children) {
      adoptNode(parent, child);
    }
    parent.childNodes.splice(index, 0, ...children);
    return;
  }
  adoptNode(parent, node);
  const nextIndex = parent.childNodes.indexOf(reference);
  if (nextIndex === -1) {
    throw new Error("reference node was detached during insert");
  }
  parent.childNodes.splice(nextIndex, 0, node);
}

function removeChildNode(parent: FakeElement | FakeDocumentFragment, node: FakeNode) {
  const index = parent.childNodes.indexOf(node);
  if (index === -1) {
    throw new Error("node is not a child of parent");
  }
  parent.childNodes.splice(index, 1);
  node.parentNode = null;
}

export function replaceBetweenNodes(start: FakeNode, end: FakeNode, content: FakeNode) {
  const parent = start.parentNode;
  if (!parent || parent !== end.parentNode) {
    throw new Error("boundary is detached");
  }
  let current = start.nextSibling;
  while (current && current !== end) {
    const next = current.nextSibling;
    parent.removeChild(current);
    current = next;
  }
  parent.insertBefore(content, end);
}

function getTextContent(node: FakeNode): string {
  if (node instanceof FakeTextNode) return node.textContent;
  if (node instanceof FakeCommentNode) return node.textContent;
  if (node instanceof FakeElement) return node.textContent;
  if (node instanceof FakeDocumentFragment) return node.textContent;
  return "";
}

export function findElement(node: FakeNode, predicate: (element: FakeElement) => boolean): FakeElement | null {
  if (node instanceof FakeElement && predicate(node)) {
    return node;
  }

  const children =
    node instanceof FakeElement ? node.childNodes :
    node instanceof FakeDocumentFragment ? node.childNodes :
    node instanceof FakeDocument ? node.body.childNodes :
    [];

  for (const child of children) {
    const found = findElement(child, predicate);
    if (found) return found;
  }

  return null;
}

export function findElements(node: FakeNode, predicate: (element: FakeElement) => boolean, out: FakeElement[] = []): FakeElement[] {
  if (node instanceof FakeElement && predicate(node)) {
    out.push(node);
  }

  const children =
    node instanceof FakeElement ? node.childNodes :
    node instanceof FakeDocumentFragment ? node.childNodes :
    node instanceof FakeDocument ? node.body.childNodes :
    [];

  for (const child of children) {
    findElements(child, predicate, out);
  }

  return out;
}

export function byClass(name: string) {
  return (element: FakeElement) => element.className.split(/\s+/).includes(name);
}

export function byTag(name: string) {
  return (element: FakeElement) => element.tagName === name;
}

export function byTagAndClass(tag: string, className: string) {
  return (element: FakeElement) => element.tagName === tag && byClass(className)(element);
}

export function click(element: FakeElement) {
  element.dispatchEvent({ type: "click", target: element });
}

export function change(element: FakeElement) {
  element.dispatchEvent({ type: "change", target: element });
}

export function dblclick(element: FakeElement) {
  element.dispatchEvent({ type: "dblclick", target: element });
}

export function keydown(element: FakeElement, key: string) {
  element.dispatchEvent({ type: "keydown", key, target: element });
}

function emitCommand(args: string[]): string {
  const proc = Bun.spawnSync({
    cmd: ["zig", "build", "run", "--", ...args],
    stdout: "pipe",
    stderr: "pipe",
    cwd: process.cwd(),
  });

  if (proc.exitCode !== 0) {
    throw new Error(`command failed: ${args.join(" ")}\n${new TextDecoder().decode(proc.stderr)}`);
  }

  return new TextDecoder().decode(proc.stdout);
}

export function emitDirectBrowserModule(componentPath: string): string {
  return emitCommand(["emit-js", componentPath]);
}

// Synchronous DOM fixtures remain explicit compatibility coverage while the
// managed compiler and plugin integration suites exercise the new default.
export function emitApp(rootPath: string, outDir: string): void {
  emitCommand(["emit-app", rootPath, outDir]);
}

export async function loadModules(files: Record<string, string>) {
  const dir = mkdtempSync(join(tmpdir(), "weiv-component-"));
  for (const [name, source] of Object.entries(files)) {
    writeFileSync(join(dir, name), source.replaceAll('"weiv:cells"', JSON.stringify(new URL("../../packages/weiv/src/runtime/cell.ts", import.meta.url).href)), "utf8");
  }

  try {
    const modules: Record<string, any> = {};
    for (const name of Object.keys(files)) {
      if (!name.endsWith(".mjs")) continue;
      const file = join(dir, name);
      modules[name] = await import(`${pathToFileURL(file).href}?t=${Date.now()}`);
    }
    return modules;
  } finally {
    rmSync(dir, { recursive: true, force: true });
  }
}

export async function importModule(file: string) {
  return import(`${pathToFileURL(file).href}?t=${Date.now()}`);
}

export function assertEqual(actual: string, expected: string, label: string) {
  if (actual !== expected) {
    throw new Error(
      `${label} mismatch\nExpected:\n${expected}\n\nActual:\n${actual}\n`
    );
  }
}

export function scopeAttr(scopeId: string): string {
  return ` data-weiv-scope="${scopeId}"`;
}

export function installDocument(document: FakeDocument) {
  (globalThis as any).document = document;
}

export function installRouterWindow(pathname: string = "/") {
  const listeners = new Map<string, Array<(event: any) => void>>();
  const location = {
    pathname,
    search: "",
    hash: "",
    origin: "http://localhost",
    href: `http://localhost${pathname}`,
  };

  function setPath(nextPath: string) {
    location.pathname = nextPath;
    location.href = `http://localhost${nextPath}${location.search}${location.hash}`;
  }

  const history = {
    state: { __weiv_key: "0" },
    pushState(state: any, _unused: string, url: string) {
      history.state = state;
      setPath(url);
    },
    replaceState(state: any, _unused: string, url: string) {
      history.state = state;
      setPath(url);
    },
    back() {},
    forward() {},
  };

  const windowObject = {
    location,
    history,
    scrollX: 0,
    scrollY: 0,
    pageXOffset: 0,
    pageYOffset: 0,
    addEventListener(name: string, handler: (event: any) => void) {
      const handlers = listeners.get(name) ?? [];
      handlers.push(handler);
      listeners.set(name, handlers);
    },
    removeEventListener(name: string, handler: (event: any) => void) {
      const handlers = listeners.get(name) ?? [];
      listeners.set(
        name,
        handlers.filter((candidate) => candidate !== handler),
      );
    },
    dispatchEvent(event: any) {
      const handlers = listeners.get(event.type) ?? [];
      for (const handler of handlers) {
        handler(event);
      }
    },
    scrollTo() {},
  };

  (globalThis as any).window = windowObject;
  (globalThis as any).history = history;
  (globalThis as any).location = location;

  return windowObject;
}

export function installJsdom(): { document: Document; window: any } {
  const { JSDOM } = require("jsdom");
  const dom = new JSDOM("<!doctype html><html><body></body></html>");
  (globalThis as any).document = dom.window.document;
  return { document: dom.window.document, window: dom.window };
}
