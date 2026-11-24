# Tests

- `check-libs.sh [package]` fails if any ELF file in the installed package has
  a shared library that `ldd` can't find, and prints the package's `Depends:`.
- `check-commands.sh` fails unless `mpirun`, `csh`, `wrf.exe`,
  `real.exe` and the WPS programs are on `PATH`.
- `run-case.sh` runs a real case: ungrib, metgrid, real and wrf, on a 10×10
  domain at 10 km over Queensland for 24 hours. It downloads its input data.

CI runs all three in the `test` stage of the `Dockerfile`, a clean
`debian:trixie-slim` with only `openmethane-wrf` installed:

```shell
docker build --target test --build-arg DEB_VERSION=4.5.1-0~local -t wrf-test .
docker run --rm -v ./tests:/opt/tests wrf-test /opt/tests/run-case.sh
```

## The case

`case/` holds the namelists. The domain and physics are those of setup-wrf's
`aust-test` domain, without the sea-surface temperature update.

The data is too large for the repository. `run-case.sh` downloads the bundle
`wrf-test-data.20261124.tar.gz` from `TEST_DATA_URL`, checks it against
`TEST_DATA_SHA256`, and unpacks it into `TEST_DATA_DIR` (default
`/tmp/wrf-test-data`) unless that already holds `geo_em.d01.nc`. It contains:

- `geo_em.d01.nc`, which geogrid produced for the domain, so geogrid and the
  geography data aren't needed.
- `gdas1.fnl0p25.2022072200.f00.grib2` and the analyses at 06, 12, 18 and 00Z
  the next day: NCEP GDAS/FNL 0.25 degree analyses
  ([DOI 10.5065/D65Q4T4Z](https://doi.org/10.5065/D65Q4T4Z)), subset to
  144–153°E, 28–17°S with
  `wgrib2 <file> -small_grib 144:153 -28:-17 <out>`.

To rebuild the bundle, download the five files from
`https://data.gdex.ucar.edu/d083003/`, subset them as above, take
`geo_em.d01.nc` from setup-wrf's `domains/aust-test`, and
`tar -czf` them flat. Upload it under a new date, and change the URL and
checksum in `run-case.sh`.
