#!/usr/bin/env bash
# Build libXray as a macOS c-archive for the packet tunnel.
# Output: build-libxray/libXray.a and build-libxray/libXray.h
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
LIBXRAY="$ROOT/libXray"
OUT="$ROOT/build-libxray"
GO_ROOT="${DATAGATE_GO_ROOT:-$ROOT/.tools/go}"

if [[ ! -d "$LIBXRAY/cgo_bridge" ]]; then
  echo "libXray submodule missing. Run: git submodule update --init libXray" >&2
  exit 1
fi

if [[ ! -x "$GO_ROOT/bin/go" ]]; then
  echo "Go toolchain not found at $GO_ROOT (need 1.26.3+ for libXray)." >&2
  echo "Install with: scripts/bootstrap-go.sh" >&2
  exit 1
fi

export PATH="$GO_ROOT/bin:$PATH"
GO_VER="$("$GO_ROOT/bin/go" version)"
echo "Using $GO_VER"

ARCH="$(uname -m)"
case "$ARCH" in
  arm64) GOARCH=arm64; APPLE_ARCH=arm64 ;;
  x86_64) GOARCH=amd64; APPLE_ARCH=x86_64 ;;
  *) echo "Unsupported arch: $ARCH" >&2; exit 1 ;;
esac

SDK_PATH="$(xcrun --sdk macosx --show-sdk-path)"
MIN_VER_FLAG="-mmacosx-version-min=13.0"
FLAGS="-isysroot ${SDK_PATH} ${MIN_VER_FLAG} -arch ${APPLE_ARCH}"

mkdir -p "$OUT"
rm -f "$OUT/libXray.a" "$OUT/libXray.h"

export GOOS=darwin
export GOARCH
export GOFLAGS="-tags=darwin"
export CC="xcrun --sdk macosx --toolchain macosx clang"
export CXX="xcrun --sdk macosx --toolchain macosx clang++"
export CGO_ENABLED=1
export CGO_CFLAGS="$FLAGS"
export CGO_CXXFLAGS="$FLAGS"
export CGO_LDFLAGS="${FLAGS} -Wl,-Bsymbolic-functions"
export DARWIN_SDK=macosx

echo "Building libXray c-archive (${GOOS}/${GOARCH})..."
(
  cd "$LIBXRAY"
  go build \
    -trimpath \
    -buildvcs=false \
    -ldflags "-s -w -buildid=" \
    -o "$OUT/libXray.a" \
    -buildmode=c-archive \
    ./cgo_bridge
)

if [[ ! -f "$OUT/libXray.a" || ! -f "$OUT/libXray.h" ]]; then
  echo "libXray build did not produce libXray.a / libXray.h in $OUT" >&2
  exit 1
fi

echo "Wrote $OUT/libXray.a"
echo "Wrote $OUT/libXray.h"
ls -lh "$OUT/libXray.a" "$OUT/libXray.h"
