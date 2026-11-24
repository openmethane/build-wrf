# build-wrf

Builds [WRF](https://github.com/wrf-model/WRF) and
[WPS](https://github.com/wrf-model/WPS) for Open Methane and publishes them as
a Debian package, `openmethane-wrf`, attached to each
[GitHub release](https://github.com/openmethane/build-wrf/releases).

Based on the original "wrf-container" created by Jared Lewis at Climate
Resource: https://github.com/climate-resource/docker-wrf.

## Package

The package is built for Debian 13 (trixie), and its dependencies name trixie
packages. Each release has `openmethane-wrf_<version>_amd64.deb` and a
`SHA256SUMS` file. The version is the WRF version and a revision that counts
the builds of it: `4.5.1-1`, `4.5.1-2`. The release tag is `v4.5.1-N`.

| Package | Contents |
| --- | --- |
| `openmethane-wrf` | `wrf.exe` and `real.exe` in `/opt/wrf/main`, the data files of `/opt/wrf/run`, the WPS programs (`geogrid.exe`, `ungrib.exe`, `metgrid.exe`, `link_grib.csh`) and tables in `/opt/wps`. Depends on the libraries the binaries link, which `dpkg-shlibdeps` generates, plus `mpich` for `mpirun` and `csh` for `link_grib.csh`. |

Not in the package: sources, object files, `ndown.exe` and `tc.exe`. The
package doesn't set `PATH`: add `/opt/wrf/main` and `/opt/wps`.

### Installing

Pin the package by URL and checksum, for example in a Dockerfile. In the file
name of a dev pre-release, GitHub shows the `~` of the version as `.`.

```dockerfile
FROM scratch AS wrf-deb
ADD --checksum=sha256:<sum> https://github.com/openmethane/build-wrf/releases/download/v4.5.1-1/openmethane-wrf_4.5.1-1_amd64.deb /

FROM debian:trixie-slim
RUN --mount=type=bind,from=wrf-deb,target=/debs \
    apt-get update && apt-get install -y /debs/*.deb
ENV PATH="/opt/wrf/main:/opt/wps:${PATH}"
```

### Testing an unmerged change downstream

Define the package as a named stage, as above, and install it from a bind
mount on that stage. BuildKit lets a build replace a named stage with
`--build-context <stage>=<source>`, without editing the Dockerfile.

Locally, from the pull request's CI artifact `debs`:

```shell
# <branch> is this repository's pull request branch
RUN_ID=$(gh run list -R openmethane/build-wrf --branch <branch> --workflow build.yaml \
  --status success --limit 1 --json databaseId -q '.[0].databaseId')
gh run download "$RUN_ID" -R openmethane/build-wrf -n debs -D debs/wrf
docker build --build-context wrf-deb=./debs/wrf -t openmethane:dev .
```

In downstream CI, or in AWS, the package needs a public URL. Run the
`Publish dev build` workflow on the pull request's branch:

```shell
gh workflow run dev-build.yaml -R openmethane/build-wrf --ref <branch>
```

It builds and tests the package as pull-request CI does, with version
`4.5.1-<N>~pr<PR>.g<sha7>`, publishes a pre-release tagged `dev-pr<PR>-<sha7>`
with the package and `SHA256SUMS`, and writes the `ADD --checksum=…` line to
the job summary. Pin that in the downstream pull request temporarily, and move
the pin to a real release before it merges. The pre-release is deleted when
this repository's pull request closes.

### Releasing

Run the `Create release` workflow (`release.yaml`) on `main`. It works out the
next revision for the WRF version in `scripts/versions.sh`, builds the package
from `main`, installs it in a clean `debian:trixie-slim` and runs the checks and
the CI case there, and only then tags `v<version>` and creates the release with
the package and `SHA256SUMS` attached. It refuses to create a release that
already exists. The release notes are generated from the merged pull requests.

Pull-request CI does the build and checks too, and uploads the package as the
`debs` artifact.

### Building

[docs/building.md](docs/building.md) lists what the build needs, the steps and
their settings, and how to build without Docker, which isn't supported.

```shell
# the package, in dist/
docker build --target deb --output type=local,dest=dist .
# install it in a clean image, check its libraries and run the CI case
docker build --target test -t wrf-test .
docker run --rm -v ./tests:/opt/tests wrf-test /opt/tests/run-case.sh
```

## The image

The `ghcr.io/openmethane/wrf` image is still published, with the same contents
as before, until setup-wrf and openmethane no longer build from it
(openmethane/build-wrf#4). `docker build .` builds it. New code should install
the package instead.
