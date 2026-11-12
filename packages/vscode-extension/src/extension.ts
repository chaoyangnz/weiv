import * as vscode from "vscode";
import { WeivDefinitionProvider } from "./definition";
import * as ts from "typescript";
import { findScriptBlock } from "./parse";
import { createVirtualScript, helperDiagnostics } from "./script-types";

export function activate(context: vscode.ExtensionContext) {
  const selector: vscode.DocumentSelector = { language: "weiv", scheme: "file" };
  const diagnostics = vscode.languages.createDiagnosticCollection("weiv-script");
  const updateDiagnostics = (document: vscode.TextDocument) => {
    if (document.languageId !== "weiv") return;
    const script = findScriptBlock(document);
    if (!script) { diagnostics.delete(document.uri); return; }
    const virtual = createVirtualScript(document.uri.fsPath, script.content);
    const items = helperDiagnostics(virtual, document.uri.fsPath).map((diagnostic) => {
      const start = script.startOffset + diagnostic.start! - virtual.offset;
      const end = start + (diagnostic.length ?? 1);
      const item = new vscode.Diagnostic(
        new vscode.Range(document.positionAt(start), document.positionAt(end)),
        ts.flattenDiagnosticMessageText(diagnostic.messageText, "\n"),
        vscode.DiagnosticSeverity.Error,
      );
      item.source = "weiv-script";
      return item;
    });
    virtual.service.dispose();
    diagnostics.set(document.uri, items);
  };

  context.subscriptions.push(
    diagnostics,
    vscode.workspace.onDidOpenTextDocument(updateDiagnostics),
    vscode.workspace.onDidChangeTextDocument((event) => updateDiagnostics(event.document)),
    vscode.workspace.onDidCloseTextDocument((document) => diagnostics.delete(document.uri)),
    vscode.languages.registerDefinitionProvider(selector, new WeivDefinitionProvider()),
    vscode.languages.registerCompletionItemProvider(selector, {
      provideCompletionItems(document, position) {
        const script = findScriptBlock(document);
        if (!script) return undefined;
        const offset = document.offsetAt(position) - script.startOffset;
        if (offset < 0 || offset > script.content.length) return undefined;
        const virtual = createVirtualScript(document.uri.fsPath, script.content);
        const file = document.uri.fsPath + ".ts";
        const completions = virtual.service.getCompletionsAtPosition(file, virtual.offset + offset, {});
        virtual.service.dispose();
        return completions?.entries
          .filter((entry) => entry.name === "emit")
          .map((entry) => new vscode.CompletionItem(entry.name, vscode.CompletionItemKind.Function));
      },
    }),
    vscode.languages.registerHoverProvider(selector, {
      provideHover(document, position) {
        const script = findScriptBlock(document);
        if (!script) return undefined;
        const offset = document.offsetAt(position) - script.startOffset;
        if (offset < 0 || offset >= script.content.length) return undefined;
        const wordRange = document.getWordRangeAtPosition(position);
        const word = wordRange ? document.getText(wordRange) : "";
        if (word !== "emit") return undefined;
        const virtual = createVirtualScript(document.uri.fsPath, script.content);
        const file = document.uri.fsPath + ".ts";
        const info = virtual.service.getQuickInfoAtPosition(file, virtual.offset + offset);
        virtual.service.dispose();
        if (!info) return undefined;
        const display = ts.displayPartsToString(info.displayParts ?? []);
        if (!display.includes("emit")) return undefined;
        return new vscode.Hover(new vscode.MarkdownString().appendCodeblock(display, "typescript"));
      },
    }),
    vscode.languages.registerSignatureHelpProvider(selector, {
      provideSignatureHelp(document, position) {
        const script = findScriptBlock(document);
        if (!script) return undefined;
        const offset = document.offsetAt(position) - script.startOffset;
        if (offset < 0 || offset > script.content.length) return undefined;
        const virtual = createVirtualScript(document.uri.fsPath, script.content);
        const file = document.uri.fsPath + ".ts";
        const info = virtual.service.getSignatureHelpItems(file, virtual.offset + offset, undefined);
        virtual.service.dispose();
        if (!info) return undefined;
        const firstPrefix = ts.displayPartsToString(info.items[0]?.prefixDisplayParts ?? []);
        if (!/^\s*emit(?:<|\()/.test(firstPrefix)) return undefined;
        const help = new vscode.SignatureHelp();
        help.signatures = info.items.map((item) => {
          const label = ts.displayPartsToString(item.prefixDisplayParts) +
            item.parameters.map((parameter) => ts.displayPartsToString(parameter.displayParts)).join(", ") +
            ts.displayPartsToString(item.suffixDisplayParts);
          return new vscode.SignatureInformation(label);
        });
        help.activeSignature = info.selectedItemIndex;
        help.activeParameter = info.argumentIndex;
        return help;
      },
    }, "(", ",")
  );
  for (const document of vscode.workspace.textDocuments) updateDiagnostics(document);
}

export function deactivate() {}
