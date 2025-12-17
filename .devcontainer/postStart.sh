#!/bin/bash

if [ -e .devcontainer/postStart.local.sh ] ; then
    echo "Running postStart.local.sh"
    .devcontainer/postStart.local.sh
fi
