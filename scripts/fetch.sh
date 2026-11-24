#!/usr/bin/env bash
# Download a source tarball and check it against scripts/checksums.sha256.
# Usage: fetch.sh <url> <file-name-in-checksums> <output-directory>

set -euo pipefail

[ "$#" -eq 3 ] || { echo "Usage: $0 <url> <name> <outdir>" >&2; exit 2; }
url="$1" name="$2" outdir="$3"
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

expected="$(awk -v n="$name" '$2 == n {print $1}' "$here/checksums.sha256")"
[ -n "$expected" ] || { echo "fetch.sh: no checksum recorded for $name" >&2; exit 1; }

mkdir -p "$outdir"
curl -fsSL --retry 3 -o "$outdir/$name" "$url"
echo "$expected  $outdir/$name" | sha256sum -c -
