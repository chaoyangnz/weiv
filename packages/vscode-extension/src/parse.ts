import * as vscode from "vscode";

export interface ScriptBlock {
  content: string;
  startOffset: number;
  startLine: number;
}

export interface TemplateBlock {
  startOffset: number;
  endOffset: number;
}

export function findScriptBlock(document: vscode.TextDocument): ScriptBlock | undefined {
  const text = document.getText();
  const openMatch = text.match(/<script\s+lang="ts">/);
  if (!openMatch || openMatch.index === undefined) return undefined;

  const contentStart = openMatch.index + openMatch[0].length;
  const closeIndex = text.indexOf("</script>", contentStart);
  if (closeIndex === -1) return undefined;

  return {
    content: text.slice(contentStart, closeIndex),
    startOffset: contentStart,
    startLine: document.positionAt(contentStart).line,
  };
}

export function findTemplateBlock(document: vscode.TextDocument): TemplateBlock | undefined {
  const text = document.getText();
  const openMatch = text.match(/<template>/);
  if (!openMatch || openMatch.index === undefined) return undefined;

  const contentStart = openMatch.index + openMatch[0].length;
  const closeIndex = text.indexOf("</template>", contentStart);
  if (closeIndex === -1) return undefined;

  return { startOffset: contentStart, endOffset: closeIndex };
}

export function isInTemplate(document: vscode.TextDocument, position: vscode.Position): boolean {
  const block = findTemplateBlock(document);
  if (!block) return false;
  const offset = document.offsetAt(position);
  return offset >= block.startOffset && offset <= block.endOffset;
}

export function getWordAt(document: vscode.TextDocument, position: vscode.Position): string | undefined {
  const range = document.getWordRangeAtPosition(position, /[a-zA-Z_$][a-zA-Z0-9_$]*/);
  if (!range) return undefined;
  return document.getText(range);
}

export function isDotAccess(document: vscode.TextDocument, position: vscode.Position): boolean {
  const line = document.lineAt(position).text;
  const range = document.getWordRangeAtPosition(position, /[a-zA-Z_$][a-zA-Z0-9_$]*/);
  if (!range) return false;
  const before = line.slice(0, range.start.character);
  return /\.\s*$/.test(before);
}

export function getDotOwner(document: vscode.TextDocument, position: vscode.Position): string | undefined {
  const line = document.lineAt(position).text;
  const range = document.getWordRangeAtPosition(position, /[a-zA-Z_$][a-zA-Z0-9_$]*/);
  if (!range) return undefined;
  const before = line.slice(0, range.start.character);
  const m = before.match(/([a-zA-Z_$][a-zA-Z0-9_$]*)\.\s*$/);
  return m ? m[1] : undefined;
}

export function resolveVariableType(scriptContent: string, varName: string): string | undefined {
  const lines = scriptContent.split("\n");
  for (const line of lines) {
    // let props: Props  /  let todos: Todo[]  /  const x: SomeType
    const m = line.match(
      new RegExp(`\\b(?:let|const|var|export\\s+let)\\s+${escapeRe(varName)}\\s*:\\s*([A-Z][a-zA-Z0-9_$]*)`)
    );
    if (m) return m[1];
  }
  // function return type: function foo(): SomeType
  for (const line of lines) {
    const m = line.match(
      new RegExp(`\\bfunction\\s+${escapeRe(varName)}\\s*\\([^)]*\\)\\s*:\\s*([A-Z][a-zA-Z0-9_$]*)`)
    );
    if (m) return m[1];
  }
  return undefined;
}

export interface TypeBlock {
  startLine: number;
  endLine: number;
}

export function findTypeBlock(scriptContent: string, typeName: string): TypeBlock | undefined {
  const lines = scriptContent.split("\n");
  const openRe = new RegExp(
    `\\b(?:export\\s+)?(?:interface|type)\\s+${escapeRe(typeName)}\\b`
  );
  for (let i = 0; i < lines.length; i++) {
    if (openRe.test(lines[i])) {
      let braceDepth = 0;
      let started = false;
      for (let j = i; j < lines.length; j++) {
        for (const ch of lines[j]) {
          if (ch === "{") { braceDepth++; started = true; }
          if (ch === "}") braceDepth--;
        }
        if (started && braceDepth <= 0) {
          return { startLine: i, endLine: j };
        }
      }
      return { startLine: i, endLine: lines.length - 1 };
    }
  }
  return undefined;
}

function escapeRe(s: string): string {
  return s.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
}

export function isComponentTag(document: vscode.TextDocument, position: vscode.Position): boolean {
  const word = getWordAt(document, position);
  if (!word || !/^[A-Z]/.test(word)) return false;
  const line = document.lineAt(position).text;
  const range = document.getWordRangeAtPosition(position, /[a-zA-Z_$][a-zA-Z0-9_$]*/);
  if (!range) return false;
  const before = line.slice(0, range.start.character);
  return /<\/?$/.test(before);
}
