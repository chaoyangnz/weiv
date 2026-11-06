export type BunPluginBuild = {
  config: { entrypoints: Array<string | { in: string }>; root?: string };
  onStart(callback: () => void | Promise<void>): void;
  onDispose(callback: () => void): void;
  onResolve(args: { filter: RegExp }, callback: (args: { path: string; importer?: string; resolveDir?: string }) => void | { path: string; namespace?: string } | Promise<void | { path: string; namespace?: string }>): void;
  onLoad(args: { filter: RegExp; namespace?: string }, callback: (args: { path: string }) => { contents: string; loader: "js" } | Promise<{ contents: string; loader: "js" }>): void;
};

export type WeivBunPlugin = {
  name: string;
  setup(build: BunPluginBuild): void;
};

export type WeivBunPluginOptions = {
  /** Managed reactivity is the default. Legacy is a deprecated migration mode. */
  reactivity?: "managed" | "legacy";
  /** Root of the modules whose state Weiv may manage. Defaults to the project root. */
  root?: string;
  /** Additional component roots for custom entry/alias loaders. */
  components?: string[];
};

export function weiv(options?: WeivBunPluginOptions): WeivBunPlugin;
