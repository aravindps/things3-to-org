#!/bin/bash
# create-repo.sh -- one-time GitHub repo creation
# Requires: brew install gh && gh auth login

set -e
cd "$(dirname "$0")"

git init
git add .
git commit -m "feat: Things3 -> org-mode backup v2.0"

gh repo create things3-org-backup \
  --private \
  --description "Export Things3 to org-mode for beorg / Emacs" \
  --source=. \
  --remote=origin \
  --push

echo "Done: https://github.com/$(gh api user -q .login)/things3-org-backup"
