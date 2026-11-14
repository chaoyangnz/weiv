#!/usr/bin/env bash
export PATH="/opt/homebrew/bin:$HOME/.bun/bin:$HOME/.cyna/current/bin:$PATH"
for node_bin in "$HOME"/.nvm/versions/node/v22*/bin /opt/neucine-release-tools/node*/bin; do
  if [ -x "$node_bin/npm" ]; then
    export PATH="$node_bin:$PATH"
    break
  fi
done
