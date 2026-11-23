#!/bin/sh
# Cloudflare Pages build: publish only the app files (not the Windows shortcut, .reg files or database notes).
set -e
rm -rf dist
mkdir -p dist
cp index.html manifest.webmanifest sw.js _headers dist/
cp -r icons vendor dist/
echo "Bilheteira: $(ls dist | wc -l) entradas publicadas em dist/"
