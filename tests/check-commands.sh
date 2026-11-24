#!/usr/bin/env bash
# Fail unless the programs the package's users run are on PATH.

set -euo pipefail

status=0
for cmd in mpirun csh wrf.exe real.exe geogrid.exe ungrib.exe metgrid.exe link_grib.csh; do
  if command -v "$cmd" >/dev/null; then
    echo "found $cmd: $(command -v "$cmd")"
  else
    echo "FAILED: $cmd is not on PATH"
    status=1
  fi
done
exit "$status"
