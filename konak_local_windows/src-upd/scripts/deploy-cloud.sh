#!/usr/bin/env bash
# Bulut VPS deploy (31.187.74.228 da ishga tushiriladi):
#   ssh root@31.187.74.228 'cd /opt/konak-cloud/src && git pull && bash scripts/deploy-cloud.sh'
#
# Nima qiladi:
#   1. Linux binar build qilib konak-cloud xizmatini yangilaydi;
#   2. Windows binarni ham cross-compile qilib artifacts/ ga qo'yadi —
#      local master (Windows) shu artefaktni ko'rib O'ZINI O'ZI yangilaydi
#      (internal/update). Ya'ni bulutga deploy = butun tizimga deploy.
set -euo pipefail

cd "$(dirname "$0")/.."
APP_DIR=/opt/konak-cloud
ART_DIR="$APP_DIR/artifacts"

git pull

COMMIT=$(git rev-parse --short HEAD)
BUILD_UNIX=$(date +%s)
VERSION="$(date +%y%m%d.%H%M)-$COMMIT"
LDFLAGS="-X konak-local/internal/version.Version=$VERSION -X konak-local/internal/version.BuildUnixStr=$BUILD_UNIX"

export GOTOOLCHAIN=auto CGO_ENABLED=0

echo "== Linux binar ($VERSION) =="
go build -ldflags "$LDFLAGS" -o "$APP_DIR/konak-cloud.new" ./cmd/server

echo "== Windows artefakt =="
mkdir -p "$ART_DIR"
GOOS=windows GOARCH=amd64 go build -ldflags "$LDFLAGS" -o "$ART_DIR/server-windows-amd64.exe" ./cmd/server
SHA=$(sha256sum "$ART_DIR/server-windows-amd64.exe" | cut -d' ' -f1)
SIZE=$(stat -c%s "$ART_DIR/server-windows-amd64.exe")
# windows.json oxirida yoziladi — chala exe ustida eski metadata turadi,
# local hech qachon chala artefaktni olmaydi.
printf '{"version":"%s","build_unix":%s,"sha256":"%s","size":%s}\n' \
  "$VERSION" "$BUILD_UNIX" "$SHA" "$SIZE" > "$ART_DIR/windows.json"

echo "== Xizmatni yangilash =="
mv "$APP_DIR/konak-cloud.new" "$APP_DIR/konak-cloud"
systemctl restart konak-cloud
systemctl is-active konak-cloud

echo "DEPLOY OK: $VERSION"
