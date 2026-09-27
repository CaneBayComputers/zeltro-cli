#!/usr/bin/env bash
# Build a .deb for the Zeltro CLI.
#
# Layout note: packages must NOT install into /usr/local -- Debian policy
# reserves that for the local administrator, and the shell installer already
# owns it. A packaged install therefore lives in /opt/zeltro-cli with a symlink
# at /usr/bin/zeltro, so the two install methods cannot collide on disk.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
VERSION_RAW="$(tr -d ' \t\n\r' < "$REPO_ROOT/VERSION")"
# Debian treats '-' as the package/revision separator, and '~' sorts BEFORE the
# release it precedes -- so 1.0.0~beta.1 correctly upgrades to 1.0.0.
VERSION_DEB="${VERSION_RAW//-/\~}"
OUT_DIR="${1:-$REPO_ROOT/dist}"
BUILD="$(mktemp -d)"
trap 'rm -rf "$BUILD"' EXIT

echo "Building zeltro-cli ${VERSION_DEB}"

install -d "$BUILD/opt/zeltro-cli" "$BUILD/usr/bin" "$BUILD/DEBIAN"
# Ship the runtime tree only: no .git, no docs site, no packaging scaffolding.
# AGENTS.md is runtime: the generated projects-dir AGENTS.md points agents at it.
for item in src VERSION LICENSE README.md AGENTS.md; do
    [ -e "$REPO_ROOT/$item" ] && cp -r "$REPO_ROOT/$item" "$BUILD/opt/zeltro-cli/"
done
ln -s /opt/zeltro-cli/src/zeltro "$BUILD/usr/bin/zeltro"

INSTALLED_KB=$(du -sk "$BUILD/opt" | cut -f1)

sed -e "s/@VERSION@/$VERSION_DEB/" -e "s/@INSTALLED_SIZE@/$INSTALLED_KB/" \
    "$REPO_ROOT/packaging/debian/control" > "$BUILD/DEBIAN/control"
install -m 0755 "$REPO_ROOT/packaging/debian/postinst" "$BUILD/DEBIAN/postinst"
install -m 0755 "$REPO_ROOT/packaging/debian/prerm"    "$BUILD/DEBIAN/prerm"

mkdir -p "$OUT_DIR"
DEB="$OUT_DIR/zeltro-cli_${VERSION_DEB}_all.deb"
dpkg-deb --build --root-owner-group "$BUILD" "$DEB" >/dev/null
echo "  -> $DEB"
dpkg-deb --info "$DEB" | sed -n '2,12p'
