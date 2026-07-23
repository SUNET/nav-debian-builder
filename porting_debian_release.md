# Porting the NAV Debian package to a new Debian release

This guide explains **what to change** when moving the NAV Debian package from
its current target (**bookworm**, Debian 12) to a newer release such as
**trixie** (Debian 13) or later, and **how to find the correct replacement
package names/versions** for the new release.

> Why this matters: this package is not pure Python. `dh-virtualenv` compiles C
> extensions and links them against the build release's shared libraries, and it
> bakes in that release's Python interpreter. So the package **must be built on
> the same release you deploy to**, and several dependency names are
> release-specific and must be updated.

---

## The golden rule

**Build on the release you deploy to.** Do not expect a bookworm-built package
to run reliably on trixie: the vendored virtualenv is tied to the build
release's Python (e.g. 3.11 on bookworm vs 3.13 on trixie) and to
release-specific library sonames (`libldap`, `libsnmp`, ...).

Build for a specific release with the release-aware script:

```bash
cd debian
DEBIAN_RELEASE=trixie ./clone-and-build.sh 5.15.0-1trixie v5.15.0 "Trixie build"
```

`DEBIAN_RELEASE` selects the docker base image (`FROM debian:${DEBIAN_RELEASE}`),
which is what actually determines the target release.

---

## Files you may need to edit

| File | What lives there | Release-sensitive? |
| ---- | ---------------- | ------------------ |
| `debian/Dockerfile` | Build environment: base image + build-time `-dev` libs + Node.js | **Yes** |
| `debian/control` | `Build-Depends` and runtime `Depends` (library soname packages, Python, PostgreSQL) | **Yes** |
| `debian/compat` / `debhelper` version | debhelper compat level | Occasionally |
| `debian/changelog` | Version + target distribution name | Yes (distribution field) |

---

## 1. `debian/Dockerfile`

### 1.1 Base image (already parameterized)

```dockerfile
ARG DEBIAN_RELEASE=bookworm
FROM debian:${DEBIAN_RELEASE}
```

Set via `DEBIAN_RELEASE=trixie`. Nothing to edit here unless you want to change
the default.

### 1.2 SNMP runtime library (release-specific soname)

`Dockerfile` line ~30 installs `libsnmp40`. **This package name changes between
releases** because the number is the library soname:

- bookworm: `libsnmp40`
- trixie: a different one (e.g. `libsnmp-base` + `libsnmp45` — verify, see below)

If the image build fails on `libsnmp40`, replace it with the trixie name.

### 1.3 Node.js workaround

Lines ~45-46 fetch Node 18 from NodeSource because bookworm's `nodejs` was too
old:

```dockerfile
RUN curl -fsSL https://deb.nodesource.com/setup_18.x | bash - && \
    apt-get install -y nodejs
```

On trixie, the distro `nodejs` is likely new enough for webpack. You can either:

- leave this as-is (works, but pins an older-ish Node), or
- drop it and add `nodejs npm` to the `apt-get install` list instead.

### 1.4 Build-time `-dev` libraries

`libpq-dev`, `libjpeg-dev`, `libldap2-dev`, `libsasl2-dev`, `libgammu-dev` are
usually stable across releases (the `-dev` names don't carry the soname). Verify
they still exist (see the lookup section).

---

## 2. `debian/control`

The runtime `Depends:` block contains **soname-versioned** package names that
are the most likely to break. Current bookworm values:

| Line | Current (bookworm) | Action on new release |
| ---- | ------------------ | --------------------- |
| `libsnmp40` (build + runtime) | soname 40 | **Update** to the release's libsnmp package |
| `libldap-2.5-0 (>= 2.5.13)` | OpenLDAP 2.5 | **Update** — trixie ships OpenLDAP 2.6, so this becomes e.g. `libldap-2.6-0` (or the meta `libldap2`) |
| `libjpeg62` | libjpeg-turbo soname 62 | Verify; usually stable, occasionally bumps |
| `libgsmsd8` (gammu runtime) | soname 8 | Verify; may bump with a new gammu |
| `libsasl2-2`, `libpq5`, `zlib1g` | | Usually stable; verify |
| `python3-distutils` | Python < 3.12 helper | **Remove** — distutils was removed in Python 3.12+, so this package does **not exist** on trixie. Leaving it makes `apt install` fail |
| `python3 (>= 3.9)` | lower bound | Fine as a lower bound; the actual runtime Python is whatever the release ships (3.13 on trixie) |
| `postgresql (>= 13)`, `postgresql-contrib (>= 13)` | | Fine as lower bounds; trixie ships a newer default (16/17) |
| `wwwconfig-common (>= 0.0.37)` | | Verify it still exists |
| `graphite-carbon`, `graphite-web` (Recommends) | | Verify names still exist |

Also review, though less likely to change:

- `Standards-Version: 3.9.6` — bump toward the current Debian Policy version of
  the target release (informational; doesn't affect the build).
- `X-Python-Version: 3.9` — informational.

---

## 3. `debian/changelog`

Set the **distribution** field to the target release name so the changelog and
package version reflect where it's meant to run:

```
nav (5.15.0-1trixie) trixie; urgency=medium
```

The `clone-and-build.sh` script sets the version via `dch`; use a version suffix
that encodes the release (e.g. `-1trixie`) so packages for different releases
sort/identify distinctly.

---

## How to find the correct package name/version for a new release

When a soname-versioned package (like `libsnmp40` or `libldap-2.5-0`) doesn't
exist on the new release, use one of these methods to find its replacement.

### Method A: Debian's package search website (no setup)

- **Find a package by name:** <https://packages.debian.org/trixie/PACKAGENAME>
- **Find which package provides a library file:** use the "Search the contents
  of packages" / file search:
  <https://packages.debian.org/trixie/> then search for e.g. `libldap` or a
  specific `.so`.
- Replace `trixie` in the URL with your target release codename.

Example: searching `libldap` for trixie shows the current runtime package
(e.g. `libldap-2.6-0`), which replaces `libldap-2.5-0`.

### Method B: apt inside the target container (most accurate)

Because you already build in a container for the exact release, query it there.
Start a shell in the target build image:

```bash
cd debian
DEBIAN_RELEASE=trixie docker build --build-arg DEBIAN_RELEASE=trixie \
    -t nav-debbuild-trixie .
docker run --rm -it nav-debbuild-trixie bash
```

Inside the container:

```bash
apt-get update

# Does a specific package exist on this release?
apt-cache policy libsnmp40            # empty Candidate => not available

# Search for the right soname package by pattern:
apt-cache search libsnmp
apt-cache search '^libldap'

# Which package provides a given library file? (install apt-file first)
apt-get install -y apt-file && apt-file update
apt-file search libldap-2.6.so
apt-file search libnetsnmp.so
```

`apt-cache search` + `apt-file search` reliably tell you the exact package name
that ships a given `.so` on that release.

### Method C: rmadison (version across releases)

```bash
# needs the devscripts package
rmadison libldap-2.5-0        # shows which releases still carry it
rmadison libsnmp40
```

Useful to confirm a name was dropped and to see what the successor is.

---

## Recommended porting workflow

1. **Try a build for the new release** and let it tell you what's missing:

   ```bash
   cd debian
   DEBIAN_RELEASE=trixie ./clone-and-build.sh 5.15.0-1trixie v5.15.0 "Trixie build"
   ```

2. **If the image build fails** on a `-dev`/lib package (e.g. `libsnmp40`), use
   Method B inside the container to find the replacement, then fix
   `debian/Dockerfile`.

3. **If `apt install` (or the build's dependency resolution) fails** on runtime
   `Depends`, fix `debian/control`:
   - remove `python3-distutils`,
   - update `libldap-2.5-0` -> the release's OpenLDAP soname,
   - update `libsnmp40` -> the release's libsnmp package,
   - verify `libjpeg62`, `libgsmsd8`, `libpq5`, `libsasl2-2`, `zlib1g`.

4. **After a successful build**, sanity-check the vendored venv on the target:

   ```bash
   # on the target-release server (or in the target container)
   apt-get install --simulate ./nav_5.15.0-1trixie_amd64.deb   # deps resolve?
   /opt/venvs/nav/bin/python -c "import psycopg2, ldap, PIL, gammu"  # C exts load?
   find /opt/venvs/nav -name '*.so' -exec ldd {} \; 2>/dev/null | grep "not found"
   ```

   No "not found" lines and clean imports mean the native libraries and Python
   ABI match the target release.

---

## Quick checklist

- [ ] `DEBIAN_RELEASE=<codename>` passed to the build
- [ ] `debian/Dockerfile`: `libsnmp40` -> release's libsnmp package
- [ ] `debian/Dockerfile`: Node.js step reviewed (keep or use distro `nodejs`)
- [ ] `debian/control`: remove `python3-distutils` (gone in Python >= 3.12)
- [ ] `debian/control`: `libldap-2.5-0` -> release's OpenLDAP soname (e.g. `libldap-2.6-0`)
- [ ] `debian/control`: `libsnmp40` -> release's libsnmp package
- [ ] `debian/control`: verify `libjpeg62`, `libgsmsd8`, `libpq5`, `libsasl2-2`, `zlib1g`, `wwwconfig-common`, graphite packages
- [ ] `debian/changelog`: distribution field + version suffix set to the release
- [ ] Post-build: `.so` files resolve and C-extension imports work on the target
