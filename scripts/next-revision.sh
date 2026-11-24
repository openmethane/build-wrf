#!/usr/bin/env bash
# Prints the next Debian revision for the WRF version in scripts/versions.sh:
# one more than the highest N among the releases tagged v<WRF version>-N, or 1.
# Needs the gh CLI and GH_TOKEN, and reads releases of $GITHUB_REPOSITORY.

set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$here/versions.sh"

tags="$(gh release list --repo "$GITHUB_REPOSITORY" --limit 1000 --json tagName -q '.[].tagName')"
# grep exits 1 when nothing matches, which is the case for a new WRF version
last="$(grep -E "^v${WRF_VERSION//./\\.}-[0-9]+\$" <<<"$tags" | sed -E 's/^.*-//' | sort -n | tail -n1 || true)"
echo $(( ${last:-0} + 1 ))
