#!/bin/bash

# Install Rust
curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y
source "$HOME/.cargo/env"

# Install asciinema and agg (gif converter) via cargo
cargo install asciinema
cargo install --git https://github.com/asciinema/agg

echo "postCreate.sh successful"

if [ -e .devcontainer/postCreate.local.sh ] ; then
    echo "Running postCreate.local.sh"
    .devcontainer/postCreate.local.sh
fi
