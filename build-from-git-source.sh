#!/bin/sh -e
#
# clone-and-build.sh
# ==================
# Self-contained procedure that lives INSIDE the packaging (debian) repo.
#
# It:
#   1. Clones the upstream NAV source repo (git@github.com:Uninett/nav.git).
#   2. Overlays THIS packaging repo's files as the cloned tree's debian/ folder.
#   3. Builds a binary-only .deb inside a Docker build environment.
#
# It does NOT rely on:
#   - an existing "nav-debian" fork,
#   - upstream git tags,
#   - the version being derived from git.
# The package version is whatever you pass on the command line.
#
# Usage:
#   ./clone-and-build.sh VERSION [UPSTREAM_REF] [CHANGELOG MESSAGE]
#
# Arguments:
#   VERSION         Debian package version, e.g. 5.15.0-1  or  5.15.0-1+test1
#   UPSTREAM_REF    (optional) branch/tag/commit of nav.git to build.
#                   Defaults to "master".
#   MESSAGE         (optional) changelog message. Defaults to a generic string.
#
# Examples:
#   ./clone-and-build.sh 5.15.0-1
#   ./clone-and-build.sh 5.15.0-1+test1 master "Test build from master"
#   ./clone-and-build.sh 5.15.0-1 v5.15.0 "Release build of 5.15.0"
#
# Target Debian release (which release the .deb is built for) is chosen via the
# DEBIAN_RELEASE environment variable (default: bookworm). It sets the docker
# base image. Examples:
#   DEBIAN_RELEASE=trixie   ./clone-and-build.sh 5.15.0-1trixie master "Trixie build"
#   DEBIAN_RELEASE=bookworm ./clone-and-build.sh 5.15.0-1
#
# Result:
#   A nav_<VERSION>_amd64.deb in the build workspace (path is printed at the end).

# ---------------------------------------------------------------------------
# Configuration (override via environment if you like)
# ---------------------------------------------------------------------------
UPSTREAM_URL="${UPSTREAM_URL:-https://github.com/Uninett/nav.git}"
# Where the throwaway source checkout + build happens:
WORKDIR="${WORKDIR:-$(pwd)/../build}"
# Target Debian release. This is the docker base image (bookworm, trixie, ...).
# It determines what release the .deb is built for.
DEBIAN_RELEASE="${DEBIAN_RELEASE:-bookworm}"
# Docker image tag for the build environment (per-release, so images don't clash):
IMAGE="${IMAGE:-nav-debbuild-$DEBIAN_RELEASE}"

# ---------------------------------------------------------------------------
# Arguments
# ---------------------------------------------------------------------------
VERSION="$1"
UPSTREAM_REF="${2:-master}"
MESSAGE="${3:-Automated package build}"

if [ -z "$VERSION" ]; then
    echo "ERROR: VERSION argument is required." >&2
    echo "Usage: $0 VERSION [UPSTREAM_REF] [CHANGELOG MESSAGE]" >&2
    exit 1
fi

# Directory that holds THIS packaging repo (the dir containing this script's
# parent 'debian' folder). We resolve it so the script works from anywhere.
PKG_DEBIAN_DIR="$(cd "$(dirname "$0")" && pwd)"          # .../debian
PKG_REPO_DIR="$(dirname "$PKG_DEBIAN_DIR")"              # the packaging repo root

echo ">>> Packaging repo:   $PKG_REPO_DIR"
echo ">>> Upstream source:  $UPSTREAM_URL @ $UPSTREAM_REF"
echo ">>> Package version:  $VERSION"
echo ">>> Debian release:   $DEBIAN_RELEASE"
echo ">>> Build workspace:  $WORKDIR"

# ---------------------------------------------------------------------------
# 1. Clone (or refresh) the upstream source
# ---------------------------------------------------------------------------
mkdir -p "$WORKDIR"
SRC_DIR="$WORKDIR/nav"

if [ -d "$SRC_DIR/.git" ]; then
    echo ">>> Updating existing upstream checkout"
    git -C "$SRC_DIR" fetch --tags origin
else
    echo ">>> Cloning upstream"
    git clone "$UPSTREAM_URL" "$SRC_DIR"
fi

echo ">>> Checking out $UPSTREAM_REF"
git -C "$SRC_DIR" checkout -f "$UPSTREAM_REF"
git -C "$SRC_DIR" reset --hard "$UPSTREAM_REF"
# Make sure no leftover debian/ or quilt state from a previous run survives:
rm -rf "$SRC_DIR/debian" "$SRC_DIR/.pc"

# ---------------------------------------------------------------------------
# 2. Overlay THIS repo's packaging files as debian/
# ---------------------------------------------------------------------------
echo ">>> Overlaying packaging files into $SRC_DIR/debian"
cp -a "$PKG_DEBIAN_DIR" "$SRC_DIR/debian"
# Don't ship the build helper scripts inside the package tree:
rm -f "$SRC_DIR/debian/clone-and-build.sh" \
      "$SRC_DIR/debian/build.sh" \
      "$SRC_DIR/debian/build_test.sh" \
      "$SRC_DIR/debian/dev.sh" \
      "$SRC_DIR/debian/dch.sh" \
      "$SRC_DIR/debian/Dockerfile" 2>/dev/null || true

# ---------------------------------------------------------------------------
# 3. Build the Docker image (build environment only; no source is COPYed in)
# ---------------------------------------------------------------------------
echo ">>> Building Docker build environment ($IMAGE) for $DEBIAN_RELEASE"
docker build --build-arg "DEBIAN_RELEASE=$DEBIAN_RELEASE" -t "$IMAGE" "$PKG_DEBIAN_DIR"

# ---------------------------------------------------------------------------
# 4. Run the build inside the container
#    - The source tree is bind-mounted, not copied.
#    - We set the changelog version with dch (no git-derived version).
#    - We build BINARY-ONLY (-b) so the strict 3.0 (quilt) source check and the
#      upstream-tag requirement in gbp.conf are bypassed. This is what lets us
#      build without any upstream tags existing.
# ---------------------------------------------------------------------------
echo ">>> Building package inside container"
docker run --rm \
    --tty \
    --user "$(id -u):$(id -g)" \
    --volume "$WORKDIR:/build" \
    --volume "$HOME/.cache:/home/.cache" \
    --workdir "/build/nav" \
    --env "DEBEMAIL=${DEBEMAIL:-packaging@example.com}" \
    --env "DEBFULLNAME=${DEBFULLNAME:-NAV Packaging}" \
    "$IMAGE" \
    sh -e -c "
        set -x
        # Force a clean, non-git changelog entry at the requested version:
        dch --create --package nav -v '$VERSION' --distribution unstable \
            '$MESSAGE' 2>/dev/null || \
        dch -b -v '$VERSION' --distribution unstable '$MESSAGE'
        # Binary-only build; no source package, no tags needed:
        dpkg-buildpackage -b -us -uc -ui -i -I
    "

# ---------------------------------------------------------------------------
# 5. Report
# ---------------------------------------------------------------------------
cat <<EOF

======================================================================
Build finished.

Your .deb should be in:
    $WORKDIR

Install it on a test server with:
    scp $WORKDIR/nav_${VERSION}_amd64.deb user@server:/tmp/
    ssh user@server 'sudo apt install -y /tmp/nav_${VERSION}_amd64.deb'
======================================================================
EOF
