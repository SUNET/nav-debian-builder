#!/bin/sh -e
#
# build_test.sh - Build a throwaway "test" NAV Debian package from the current
# working tree (including any uncommitted changes under python/nav), for
# installing on a test server.
#
# It builds a BINARY-ONLY package (debuild -b). Binary-only builds skip the
# "dpkg-source -b" step, so the strict 3.0 (quilt) source check never runs. That
# avoids the "aborting due to unexpected upstream changes" error you otherwise
# get when your working tree differs from the pristine upstream tag (e.g. commits
# ahead of the tag, or local uncommitted edits under python/nav).
#
# The binary build (dh + dh-virtualenv) installs NAV directly from your working
# tree, so your python/nav changes DO end up in the resulting .deb.
#
# Usage:
#   ./build_test.sh [VERSION] [CHANGELOG MESSAGE]
#
# Examples:
#   ./build_test.sh                       # uses default version "5.15.0-2bookworm+test1"
#   ./build_test.sh 5.15.0-2bookworm+test2
#   ./build_test.sh 5.15.0-2bookworm+test2 "Testing my nav changes"
#
# The resulting .deb is placed in the grandparent of this debian/ folder,
# ready to scp to a test server and install with:
#   sudo apt install ./nav_<version>_amd64.deb

VERSION="${1:-5.15.0-2bookworm+test1}"
MESSAGE="${2:-Local test build with working-tree changes}"

# 0. Clear any stale quilt state left behind by a previously aborted build.
#    An interrupted build can leave debian/patches half-applied with an
#    inconsistent .pc/ directory, which makes the next build's dh_quilt_unpatch
#    fail with "Patch ... does not remove cleanly". The .pc/ directory is just
#    quilt bookkeeping (git-ignored), so removing it is safe: the build re-applies
#    the patches from scratch. We only do this when the working tree is otherwise
#    in the unpatched state (the normal committed state).
rm -rf ../.pc .pc 2>/dev/null || true

# 1. Update the Debian changelog with the test version (runs inside the container)
./dch.sh -v "$VERSION" "$MESSAGE"

# 2. Build a binary-only package inside the Docker container. The -b flag makes
#    dpkg-buildpackage skip source-package generation (no dpkg-source -b), so the
#    strict quilt upstream-changes check is bypassed.
NONINTERACTIVE=1 ./dev.sh gbp buildpackage \
    --git-ignore-new \
    --git-builder="debuild --no-lintian -b -i -I -us -uc"

output=$(dirname $(dirname "$PWD"))
cat <<EOF

Test package built with version: ${VERSION}

You should find your .deb ready for testing in:
${output}

Install it on a test server with:
  scp ${output}/nav_${VERSION}_amd64.deb user@server:/tmp/
  ssh user@server 'sudo apt install -y /tmp/nav_${VERSION}_amd64.deb'
EOF
