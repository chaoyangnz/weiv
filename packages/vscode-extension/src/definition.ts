import * as vscode from "vscode";
import * as path from "path";
import {
  findScriptBlock, isInTemplate, getWordAt, isComponentTag,
  isDotAccess, getDotOwner, resolveVariableType, findTypeBlock,
} from "./parse";

export class WeivDefinitionProvider implements vscode.DefinitionProvider {
  provideDefinition(
    document: vscode.TextDocument,
    position: vscode.Position,
    _token: vscode.CancellationToken
  ): vscode.ProviderResult<vscode.Definition> {
    if (!isInTemplate(document, position)) return undefined;

    const word = getWordAt(document, position);
    if (!word) return undefined;

    const script = findScriptBlock(document);
    if (!script) return undefined;

    if (isComponentTag(document, position)) {
      return this.findImport(document, script, word);
    }

    const decl = this.findDeclaration(document, script, word);
    if (decl) return decl;

    if (isDotAccess(document, position)) {
      const owner = getDotOwner(document, position);
      if (owner) {
        const typeName = resolveVariableType(script.content, owner);
        if (typeName) {
          const typed = this.findFieldInType(document, script, word, typeName);
          if (typed) return typed;
        }
      }
      return this.findInterfaceField(document, script, word);
    }

    return undefined;
  }

  private findDeclaration(
    document: vscode.TextDocument,
    script: { content: string; startLine: number },
    identifier: string
  ): vscode.Location | undefined {
    const patterns = [
      new RegExp(`\\bfunction\\s+(${escapeRegExp(identifier)})\\s*\\(`),
      new RegExp(`\\blet\\s+(${escapeRegExp(identifier)})\\b`),
      new RegExp(`\\bconst\\s+(${escapeRegExp(identifier)})\\b`),
      new RegExp(`\\bvar\\s+(${escapeRegExp(identifier)})\\b`),
    ];

    const lines = script.content.split("\n");
    for (let i = 0; i < lines.length; i++) {
      for (const pat of patterns) {
        const m = pat.exec(lines[i]);
        if (m && m[1]) {
          const col = m.index + m[0].indexOf(m[1]);
          const pos = new vscode.Position(script.startLine + i, col);
          return new vscode.Location(document.uri, pos);
        }
      }
    }

    return undefined;
  }

  private findFieldInType(
    document: vscode.TextDocument,
    script: { content: string; startLine: number },
    fieldName: string,
    typeName: string
  ): vscode.Location | undefined {
    const block = findTypeBlock(script.content, typeName);
    if (!block) return undefined;

    const lines = script.content.split("\n");
    const fieldRe = new RegExp(`^\\s+(${escapeRegExp(fieldName)})\\s*[?]?\\s*:`);

    for (let i = block.startLine; i <= block.endLine; i++) {
      const m = fieldRe.exec(lines[i]);
      if (m && m[1]) {
        const col = lines[i].indexOf(m[1]);
        return new vscode.Location(
          document.uri,
          new vscode.Position(script.startLine + i, col)
        );
      }
    }
    return undefined;
  }

  private findInterfaceField(
    document: vscode.TextDocument,
    script: { content: string; startLine: number },
    fieldName: string
  ): vscode.Location | undefined {
    const lines = script.content.split("\n");
    const fieldRe = new RegExp(`^\\s+(${escapeRegExp(fieldName)})\\s*[?]?\\s*:`);

    for (let i = 0; i < lines.length; i++) {
      const m = fieldRe.exec(lines[i]);
      if (m && m[1]) {
        const col = lines[i].indexOf(m[1]);
        return new vscode.Location(
          document.uri,
          new vscode.Position(script.startLine + i, col)
        );
      }
    }

    return undefined;
  }

  private findImport(
    document: vscode.TextDocument,
    script: { content: string; startLine: number },
    componentName: string
  ): vscode.Location | undefined {
    const importRe = new RegExp(
      `import\\s+(${escapeRegExp(componentName)})\\s+from\\s+["']([^"']+)["']`
    );
    const lines = script.content.split("\n");
    for (let i = 0; i < lines.length; i++) {
      const m = importRe.exec(lines[i]);
      if (m) {
        const importPath = m[2];
        const resolved = this.resolveImportPath(document, importPath);
        if (resolved) {
          return new vscode.Location(resolved, new vscode.Position(0, 0));
        }
        const col = lines[i].indexOf(componentName);
        return new vscode.Location(
          document.uri,
          new vscode.Position(script.startLine + i, col >= 0 ? col : 0)
        );
      }
    }
    return undefined;
  }

  private resolveImportPath(document: vscode.TextDocument, importPath: string): vscode.Uri | undefined {
    if (!importPath.startsWith(".")) return undefined;
    const dir = path.dirname(document.uri.fsPath);
    const resolved = path.resolve(dir, importPath);
    return vscode.Uri.file(resolved);
  }
}

function escapeRegExp(s: string): string {
  return s.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
}
