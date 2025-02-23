#!/bin/zsh

# Activate virtual environment and run kcc-c2e
source ~/.kcc/venv/bin/activate
kcc-c2e "$@"
deactivate 