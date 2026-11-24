# Building WRF and WPS

The supported build is the `Dockerfile`, which produces the Debian package
described in the [README](../README.md). Every build step there is a script in
`scripts/`, and those are the commands described here. Building outside Docker
isn't supported, but everything needed to do it is written down below, and a CI
job ([`native-build.yaml`](../.github/workflows/native-build.yaml)) follows this
document literally, on a GitHub-hosted runner with no container. The commands in
the fenced blocks that follow a `<!-- ci:run -->` marker are the ones it runs.

## What you need

Tools and libraries, by Debian 13 (trixie) package name and what they are:

| Package | What it is |
| --- | --- |
| `build-essential` | C compiler, `make` |
| `gfortran` | Fortran compiler |
| `cmake` | builds Jasper |
| `m4`, `csh` | WRF's build uses both; WPS's `link_grib.csh` needs `csh` to run |
| `libmpich-dev` | MPICH, for the parallel WRF (`mpif90`, `mpicc`) |
| `libnetcdf-dev`, `libnetcdff-dev` | netCDF C and Fortran, with `nc-config` and `nf-config` |
| `libpng-dev`, `zlib1g-dev` | GRIB2 compression in WPS |
| `curl`, `ca-certificates` | download the source tarballs |
| `mpich` | `mpirun`, to run WRF |

<!-- ci:run -->
```bash
sudo apt-get update
sudo apt-get install -y --no-install-recommends \
  ca-certificates curl build-essential cmake m4 csh gfortran \
  libmpich-dev libnetcdf-dev libnetcdff-dev libpng-dev zlib1g-dev mpich
```

On another system, find the same things under their own names. Only gfortran
and MPICH have been tried.

## Where it builds

WRF is built in `/opt/wrf`, WPS in `/opt/wps`, Jasper is installed into
`/opt/jasper`. These are also the paths they run
from, and the paths in the package: nothing is moved after the build. The
directories must be writable.

<!-- ci:run -->
```bash
sudo mkdir -p /opt/wrf /opt/wps /opt/jasper
sudo chown "$USER" /opt/wrf /opt/wps /opt/jasper
```

## The steps

Run from the root of this repository. Each script downloads its source tarball
and stops unless it matches the SHA-256 recorded in
[`scripts/checksums.sha256`](../scripts/checksums.sha256).

| Step | Script | Builds |
| --- | --- | --- |
| Jasper | `scripts/build_jasper.sh` | a static Jasper, which WPS links into `ungrib.exe` for JPEG2000 GRIB2 data. Debian trixie has no package for it |
| WRF and WPS | `scripts/build_wrf.sh` | WRF (`em_real`, dmpar, gfortran) and WPS (serial, gfortran, GRIB2) |

<!-- ci:run -->
```bash
scripts/build_jasper.sh
scripts/build_wrf.sh
```

`build_wrf.sh` needs root or `sudo`: WRF's and WPS's `configure` look for the
HDF5 and netCDF-Fortran libraries in places Debian doesn't put them, so it
adds two symlinks under `/usr/lib`.

## Versions and environment variables

The versions are in [`scripts/versions.sh`](../scripts/versions.sh), where each
can be overridden by an environment variable of the same name. Changing one
needs its checksum added to `scripts/checksums.sha256`.

| Variable | Default | Meaning |
| --- | --- | --- |
| `WRF_VERSION` | `4.5.1` | WRF release to build. Also the version of the package |
| `WPS_VERSION` | `4.5` | WPS release to build |
| `JASPER_VERSION` | `4.2.5` | Jasper release |
| `WRF_DIR` | `/opt/wrf` | where WRF is built and runs from |
| `WPS_DIR` | `/opt/wps` | where WPS is built and runs from |
| `JASPER_PREFIX` | `/opt/jasper` | where Jasper is installed, and where WPS looks for it |
| `JASPERLIB`, `JASPERINC` | `$JASPER_PREFIX/lib`, `$JASPER_PREFIX/include` | read by WPS's `configure` to find Jasper |

`build_wrf.sh` also sets, for WRF's and WPS's `configure` and compile:
`NETCDF` and `NETCDF_LDFLAGS` (from `nc-config` and `nf-config`), `NETCDF4=1`,
`HDF5_PATH`, the compilers (`gcc`, `g++`, `gfortran`), and
`FCFLAGS`/`FFLAGS` with `-fallow-argument-mismatch`.

### What `configure` is told

- **WRF:** option 34 on `x86_64` (`dmpar` with gfortran), 11 on `aarch64`, with
  basic nesting. Then `./compile em_real`.
- **WPS:** option 1 (serial, gfortran, GRIB2), then `./compile`.
- GCC 14 turns several old C constructs into errors, so both builds add
  `-Wno-error=implicit-function-declaration`, `-Wno-error=implicit-int`,
  `-Wno-error=int-conversion` and `-Wno-error=incompatible-pointer-types`.
- WPS 4.5 reads an uninitialised variable that makes `metgrid.exe` write empty
  files under gfortran 14, so its Fortran flags get `-finit-logical=false`.
  The build fails if that patch doesn't apply.

## What the build produces

The package, `openmethane-wrf`, is the runtime part of the build, made by
`scripts/package.sh` (which uses `scripts/build-deb.sh`):

| Path | |
| --- | --- |
| `/opt/wrf/main/wrf.exe`, `/opt/wrf/main/real.exe` | the model and its initialiser |
| `/opt/wrf/run/*` | the data files WRF reads (physics tables, lookup data). Symlinks are followed, since some link into the build tree, and the `.exe` links are left out |
| `/opt/wps/geogrid.exe`, `ungrib.exe`, `metgrid.exe`, `link_grib.csh` | the WPS programs (symlinks followed) |
| `/opt/wps/geogrid/GEOGRID.TBL*`, `/opt/wps/metgrid/METGRID.TBL*` | WPS tables |
| `/opt/wps/ungrib/Variable_Tables/` | the Vtables |

Not in it: the sources, object files, `ndown.exe` and `tc.exe`. Its `Depends:`
is generated by `dpkg-shlibdeps` over every ELF file, plus `mpich` for `mpirun`
and `csh` for `link_grib.csh`, which nothing links against. The package doesn't
set `PATH`: add `/opt/wrf/main` and `/opt/wps`.

## Testing

`tests/run-case.sh` runs ungrib, metgrid, real and wrf on a small case with the
programs on `PATH`, as in the `test` stage of the `Dockerfile`. It downloads
its input data (`curl` and `ca-certificates`, installed above). See
[tests/README.md](../tests/README.md).

## Known limitations

- Only gfortran and MPICH have been tried.
- `scripts/configure.aarch64` exists, but `arm64` isn't built in CI.
- The native build job runs on Ubuntu, with its own compiler version, rather
  than on Debian 13. The package is only tested on Debian 13.
- The build assumes `/usr/lib` can be written, through `sudo`, and that
  `/opt/wrf` and `/opt/wps` are free.
