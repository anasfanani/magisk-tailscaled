#!/bin/bash
set -e

VERSION="${1:-$(grep '^version=' module.prop | cut -d'=' -f2)}"
DIST_DIR="dist"
BIN_DIR="tailscale/bin"

get_latest_release() {
  curl -s "https://api.github.com/repos/$1/releases/latest" | grep '"browser_download_url"' | grep "$2" | sed 's/.*"browser_download_url": "\([^"]*\)".*/\1/'
}

echo "Building Magisk-Tailscaled ${VERSION}"
echo "========================================"

mkdir -p "$BIN_DIR" "$DIST_DIR"

echo "Downloading binaries..."
for ARCH in arm arm64; do
  case $ARCH in
    arm) F_ARCH=armv7a ;;
    arm64) F_ARCH=aarch64 ;;
  esac
  
  echo "- Downloading tailscaled for ${ARCH}..."
  URL=$(get_latest_release "anasfanani/tailscale-android-cli" "tailscale_.*_${ARCH}\.tgz")
  curl -#L "$URL" | tar -xz -C "$BIN_DIR"
  mv "$BIN_DIR/tailscaled" "$BIN_DIR/tailscaled-$ARCH"
  
  echo "- Downloading jq for ${ARCH}..."
  URL=$(get_latest_release "theshoqanebi/jq-build-for-android" "jq-${F_ARCH}-linux-android")
  curl -#L "$URL" -o "$BIN_DIR/jq-$ARCH"
done

echo ""
echo "Creating zip without binaries..."
zip -9 -r "${DIST_DIR}/Magisk-Tailscaled-${VERSION}.zip" . -x "*.git*" "dist/*" "tests/*" "docs/*" "*.zip" "*.json" "*.md" "${BIN_DIR}/*" ".shellcheckrc" >/dev/null

for ARCH in arm arm64; do
  (cd "$BIN_DIR" && sha256sum "tailscaled-$ARCH" > "SHA256SUMS-$ARCH")
done
echo "Creating zip with binaries..."
zip -9 -r "${DIST_DIR}/Magisk-Tailscaled-${VERSION}-full.zip" . -x "*.git*" "dist/*" "tests/*" "docs/*" "*.zip" "*.json" "*.md" ".shellcheckrc" >/dev/null

rm -f "$BIN_DIR"/*

echo ""
echo "Build completed successfully!"
echo "========================================"
ls -lh "${DIST_DIR}/"
echo "========================================"
echo "Created: ${DIST_DIR}/Magisk-Tailscaled-${VERSION}.zip (no binaries - downloads on install)"
echo "Created: ${DIST_DIR}/Magisk-Tailscaled-${VERSION}-full.zip (includes all binaries)"

