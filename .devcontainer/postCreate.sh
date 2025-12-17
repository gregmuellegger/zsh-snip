#!/bin/bash

echo "postCreate.sh successful"

if [ -e .devcontainer/postCreate.local.sh ] ; then
    echo "Running postCreate.local.sh"
    .devcontainer/postCreate.local.sh
fi
