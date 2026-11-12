# VS Code Extension

Weiv has a dedicated VS Code extension for `.weiv` files.

![Weiv VS Code extension preview](./assets/weiv-vscode-preview.png)

Source: [`packages/vscode-extension`](https://github.com/neucine/weiv/tree/main/packages/vscode-extension).

## What It Adds

- syntax highlighting for `.weiv`
- embedded HTML, TypeScript, and CSS language support
- Weiv-specific highlighting for directives and interpolation
- go-to-definition support for component imports and script symbols used from templates
- file icon support for `.weiv`

## Install

If the extension is published in the Marketplace, install `Weiv` there.

For a local build from the Weiv repository:

```bash
git clone https://github.com/neucine/weiv.git
cd weiv/packages/vscode-extension
npm ci
npm run package
code --install-extension weiv-vscode-0.1.0.vsix
```

## Recommended Workflow

1. Install `weivjs` in your project.
2. Install the VS Code extension.
3. Open your `.weiv` app in VS Code.
4. Use the extension for syntax highlighting and navigation while using the `weiv` CLI for dev/build flows.
