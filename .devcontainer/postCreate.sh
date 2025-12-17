#!/bin/bash

# Install asciinema for recording terminal demos
sudo apt-get update && sudo apt-get install -y asciinema

echo "postCreate.sh successful"

if [ -e .devcontainer/postCreate.local.sh ] ; then
    echo "Running postCreate.local.sh"
    .devcontainer/postCreate.local.sh
fi
