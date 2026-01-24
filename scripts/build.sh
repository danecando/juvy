#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
manifest="$repo_root/scripts/build.manifest"
out="$repo_root/juvy.zsh"

if [[ ! -f "$manifest" ]]; then
  echo "Missing build manifest: $manifest" >&2
  exit 1
fi

tmp="$(mktemp)"

while IFS= read -r line || [[ -n "$line" ]]; do
  [[ -z "$line" ]] && continue
  [[ "$line" == \#* ]] && continue

  src="$repo_root/$line"
  if [[ ! -f "$src" ]]; then
    echo "Missing source file: $src" >&2
    rm -f "$tmp"
    exit 1
  fi

  cat "$src" >> "$tmp"
  printf '\n' >> "$tmp"
done < "$manifest"

mv "$tmp" "$out"
chmod +x "$out"

echo "Built $out"
