#!/usr/bin/env bash
# Smoke test: Crayfish's Apache starts and passes its healthcheck, the three
# microservices are installed, and the conversion tools they shell out to work.
# Usage: test/smoke.sh <image>
set -euo pipefail
IMAGE="${1:?usage: $0 <image>}"
NAME="crayfish-smoke-$$"
trap 'rc=$?; [ $rc -ne 0 ] && docker logs "$NAME" >&2 2>&1; docker rm -f "$NAME" >/dev/null 2>&1; exit $rc' EXIT

docker run -d --name "$NAME" "$IMAGE" >/dev/null

echo "waiting for the healthcheck endpoint..."
for _ in $(seq 1 30); do
  docker exec "$NAME" /healthcheck.sh >/dev/null 2>&1 && up=1 && break
  [ "$(docker inspect -f '{{.State.Running}}' "$NAME")" = "true" ] || { echo "FAIL: container exited" >&2; exit 1; }
  sleep 1
done
[ "${up:-0}" = "1" ] || { echo "FAIL: /healthz never returned 200" >&2; exit 1; }
echo "ok: /healthz 200"

for svc in Homarus Houdini Hypercube; do
  docker exec "$NAME" test -d "/opt/www/crayfish/$svc/vendor" || { echo "FAIL: $svc not installed" >&2; exit 1; }
done
echo "ok: Homarus, Houdini, Hypercube installed"

docker exec "$NAME" php -v | head -1
docker exec "$NAME" sh -c '
  set -e
  ffmpeg -version | head -1
  tesseract --version 2>&1 | head -1
  gs --version
  pdftoppm -v 2>&1 | head -1
  # ImageMagick can render an image using the shipped policy.
  convert -size 64x64 xc:blue /tmp/smoke.png
  identify /tmp/smoke.png
'
echo "ok: ffmpeg, tesseract, ghostscript, poppler, ImageMagick run"
echo "smoke test passed"
