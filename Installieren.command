#!/bin/bash
set -e
DIR="$(cd "$(dirname "$0")" && pwd)"
APP="$(ls "$DIR" | grep '\.app$' | head -1)"
rm -rf "/Applications/$APP"
cp -R "$DIR/$APP" /Applications/
xattr -dr com.apple.quarantine "/Applications/$APP"
open "/Applications/$APP"
