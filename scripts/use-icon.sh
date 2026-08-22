#!/bin/bash
# Wires an Icon Composer document (.icon) in as Locker's app icon.
#
#   ./scripts/use-icon.sh ~/Desktop/Locker.icon
#
# Icon Composer (bundled with Xcode 26) saves a .icon document. Xcode compiles
# it into the layered icon macOS 26 uses, so it replaces the asset-catalog icon
# rather than living beside it.
set -euo pipefail
cd "$(dirname "$0")/.."

SOURCE="${1:-}"
if [ -z "$SOURCE" ]; then
  echo "usage: ./scripts/use-icon.sh /path/to/YourIcon.icon"
  exit 1
fi
if [ ! -e "$SOURCE" ]; then
  echo "No such file: $SOURCE"; exit 1
fi
case "$SOURCE" in
  *.icon) ;;
  *) echo "Expected a .icon document from Icon Composer, got: $SOURCE"; exit 1 ;;
esac

DEST="Locker/Resources/Locker.icon"
rm -rf "$DEST"
cp -R "$SOURCE" "$DEST"
echo "==> Installed $DEST"

# Point the build at the .icon document instead of the asset-catalog icon set.
python3 - <<'PY'
import pathlib
p = pathlib.Path("project.yml")
s = p.read_text()
if "ASSETCATALOG_COMPILER_APPICON_NAME: Locker\n" not in s:
    s = s.replace("ASSETCATALOG_COMPILER_APPICON_NAME: AppIcon",
                  "ASSETCATALOG_COMPILER_APPICON_NAME: Locker")
    p.write_text(s)
    print("==> project.yml now uses Locker.icon")
else:
    print("==> project.yml already set")
PY

xcodegen generate >/dev/null
echo "==> Regenerated the Xcode project"
echo
echo "Build it with:  ./scripts/release.sh"
