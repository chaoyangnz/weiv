export type WeivVitePlugin = import("vite").Plugin;

export type WeivVitePluginOptions = {
  /** Managed reactivity is the default. Legacy is a deprecated migration mode. */
  reactivity?: "managed" | "legacy";
  /** Root of the modules whose state Weiv may manage. Defaults to Vite's root. */
  root?: string;
  /** Additional component roots for custom entry/alias loaders. */
  components?: string[];
};

export function weiv(options?: WeivVitePluginOptions): WeivVitePlugin;
