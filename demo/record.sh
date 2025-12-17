#!/bin/zsh

set -e

sudo rm -rf /zsh-snip-demo
sudo mkdir -p /zsh-snip-demo
sudo chown $USER:$USER /zsh-snip-demo

cd /zsh-snip-demo

$HOME/.cargo/bin/asciinema record --window-size 80x24 --idle-time-limit=2 --overwrite -c 'ZDOTDIR=/workspaces/snip/demo zsh' /workspaces/snip/demo/demo.cast

agg /workspaces/snip/demo/demo.cast /workspaces/snip/demo/demo.gif
