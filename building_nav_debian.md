# NAV Debian Package — Build & Test Status

This document describes how the NAV Debian package is built and how a test build is rolled out to the `norpan-nav` host via Cosmos/Puppet. The Debian package is produced by the [nav-debian-builder](https://github.com/SUNET/nav-debian-builder) repository.

## Build locally

Clone the builder and run the build script. The script wraps the NAV source in a `.deb` and drops the artifacts into `$WORKDIR`.

```bash
git clone git@github.com:SUNET/nav-debian-builder.git
export UPSTREAM_URL=https://github.com/Uninett/nav.git
export WORKDIR="${WORKDIR:-$(pwd)/../build}"          # where to put artifacts
export DEBIAN_RELEASE=trixie
export IMAGE="${IMAGE:-nav-debbuild-$DEBIAN_RELEASE}"  # docker tag
# args = [version, upstream_branch, message]
./build-from-git-source.sh 5.15.0-1+test1 master "Test build from master"
```

Notes:

- `UPSTREAM_URL` points at the upstream NAV repository; the builder checks out the branch you pass as the second argument.
- `DEBIAN_RELEASE` must match the target host's Debian release (`trixie`).
- The version string (first argument) becomes the package version and, for GitHub releases, part of the download path (see below).

## Build with GitHub Actions

1. Go to <https://github.com/SUNET/nav-debian-builder/actions>.
2. Select the **Build Debian package** workflow.
3. Click **Run workflow**.
4. Fill in the inputs: `branch`, Debian package version, upstream branch,
   message, Debian release, and `is_release`.
5. Click **Run workflow**.

If `is_release` is selected, the resulting `.deb` is published as a GitHub release and becomes available at:

<https://github.com/SUNET/nav-debian-builder/releases>

Only released artifacts are downloadable by the host, because Puppet fetches the package from the releases download URL (see below).

## Deploy a test build to `norpan-nav`

Testing is driven entirely by the `cnaas::norpan_nav` parameters in `cosmos-rules.yaml`. The current rule is:

```yaml
'^norpan-nav1.cnaas.sunet.se$':
  cnaas::cnaas_wg:
  sunet::certbot::acmed:
  cnaas::norpan_nav:
    # prod version (exact match, incl. distro suffix as shown by `apt-cache madison nav`)
    nav_version: '5.16.1-3trixie1'
    # test/prod switch: true = side-load test deb from GitHub + apt-mark hold
    nav_test_enabled: true
    nav_test_version: '5.19.0-70-gad8b959b7-1+gh4'
    nav_test_repo: 'SUNET/nav-debian-builder'
    nav_test_arch: 'amd64'
    servicename: 'norpan-nav.dev'
    front_clients: 'norpan_front_clients'
    argus_endpoint: 'norpan-argus.dev.cnaas.sunet.se'
    argus_api_version: 'v2'
    oidc_provider_url: 'https://norpan-keycloak1.cnaas.sunet.se/realms/norpan/.well-known/openid-configuration'
    groups:
    - 'sunet-networking'
    - 'sunet-noc'
```

### How the test switch works

The `nav_test_*` parameters are consumed by `norpan_nav_components/nav.pp`, which side-loads the test `.deb` instead of installing the prod package from apt:

- When `nav_test_enabled: true`, Puppet downloads `nav_${nav_test_version}_${nav_test_arch}.deb` from
  `https://github.com/<nav_test_repo>/releases/download/nav-<debian_version>-<nav_test_version>/` into `/var/cache/nav-test/`, installs it with `apt-get install --allow-downgrades`, and then runs `apt-mark hold nav`.
  The hold prevents apt / unattended-upgrades from replacing the test build with a higher-versioned prod package.
- When `nav_test_enabled: false` (or the `nav_test_*` keys are removed), Puppet releases the hold (`apt-mark unhold nav`) and pins the package back to `nav_version` via apt — i.e. it returns to the prod version.

So `nav_test_version` is the release under <https://github.com/SUNET/nav-debian-builder/releases> that you want to run on `norpan-nav`. Removing the `nav_test_*` keys reverts the host to the prod version in `nav_version`.

> Important: the `nav_test_version` must correspond to an existing GitHub **release** (built with `is_release` enabled), because the download URL points at the releases path. A plain workflow-artifact build will not be reachable.

### Verifying on the host

```bash
# installed version
dpkg-query -W -f='${Version}\n' nav

# is the test build held?
apt-mark showhold | grep -qx nav && echo "held (test mode)" || echo "not held"

# available versions from apt
apt-cache madison nav
```

The `nav_version` value must be an exact match to what `apt-cache madison nav`
reports, including the distro suffix (e.g. `5.16.1-3trixie1`).
