import * as ts from "typescript";

export interface VirtualScript {
  source: string;
  offset: number;
  service: ts.LanguageService;
}

export function createVirtualScript(fileName: string, content: string): VirtualScript {
  const hasEmits = /\b(?:export\s+)?interface\s+Emits\b/.test(content);
  const declarations = hasEmits
    ? "declare function emit<K extends keyof Emits>(name: K, ...payload: Emits[K] extends void ? [] : [value: Emits[K]]): void;\n"
    : "declare function emit(name: string, payload?: unknown): void;\n";
  const prefix = declarations;
  const source = prefix + content;
  const virtualFile = fileName + ".ts";
  const options: ts.CompilerOptions = {
    target: ts.ScriptTarget.ES2020,
    module: ts.ModuleKind.ESNext,
    moduleResolution: ts.ModuleResolutionKind.Node10,
    strict: true,
    noEmit: true,
  };
  const host: ts.LanguageServiceHost = {
    getScriptFileNames: () => [virtualFile],
    getScriptVersion: () => "1",
    getScriptSnapshot: (name) => name === virtualFile
      ? ts.ScriptSnapshot.fromString(source)
      : ts.sys.fileExists(name) ? ts.ScriptSnapshot.fromString(ts.sys.readFile(name) ?? "") : undefined,
    getCurrentDirectory: () => ts.sys.getCurrentDirectory(),
    getCompilationSettings: () => options,
    getDefaultLibFileName: ts.getDefaultLibFilePath,
    fileExists: ts.sys.fileExists,
    readFile: ts.sys.readFile,
    readDirectory: ts.sys.readDirectory,
  };
  return { source, offset: prefix.length, service: ts.createLanguageService(host) };
}

export function helperDiagnostics(virtual: VirtualScript, fileName: string): ts.Diagnostic[] {
  const file = fileName + ".ts";
  const sourceFile = virtual.service.getProgram()?.getSourceFile(file);
  if (!sourceFile) return [];
  return virtual.service.getSemanticDiagnostics(file).filter((diagnostic) => {
    if (diagnostic.start === undefined || diagnostic.start < virtual.offset) return false;
    let nearestCall: ts.CallExpression | undefined;
    const visit = (node: ts.Node) => {
      if (diagnostic.start! < node.getStart(sourceFile) || diagnostic.start! >= node.getEnd()) return;
      if (ts.isCallExpression(node)) nearestCall = node;
      ts.forEachChild(node, visit);
    };
    visit(sourceFile);
    return nearestCall !== undefined && ts.isIdentifier(nearestCall.expression) &&
      nearestCall.expression.text === "emit";
  });
}
