#!/usr/bin/env bash
# safe-restart.sh — restart one or more firecrawl compose services and
# always follow up with an `api` restart to avoid stale DNS resolution.
#
# Root cause (found 2026-07-20 during the resource-cap upgrade pass):
# when redis/rabbitmq/nuq-postgres get recreated (new container = new
# internal IP), the long-lived `api` container's already-open Node/ioredis
# connections can go stale and start failing DNS lookups
# (`getaddrinfo EAI_AGAIN redis`) even though the hostname itself is still
# valid — Docker's embedded DNS doesn't retroactively fix an
# already-established bad resolution. `api` looks "up" in `docker compose ps`
# the whole time; you only notice via `curl: (000)` or crawl requests
# hanging until you look at the logs.
#
# Usage: ./scripts/safe-restart.sh redis rabbitmq nuq-postgres
#        ./scripts/safe-restart.sh          # restarts nothing extra, just api
#
# Always run this instead of a bare `docker compose up -d <service>` for any
# service api depends on (redis, rabbitmq, nuq-postgres, playwright-service).

set -euo pipefail
cd "$(dirname "$0")/.."

if [ "$#" -gt 0 ]; then
  echo "==> Recreating: $*"
  docker compose up -d "$@"
fi

echo "==> Restarting api to force fresh upstream connections"
docker compose up -d api

echo "==> Waiting for api to report healthy"
sleep 8
docker compose logs api --tail=20 | grep -iE "EAI_AGAIN|econnrefused" \
  && { echo "WARN: api still shows stale connection errors, check manually"; exit 1; } \
  || echo "PASS: api restarted clean, no stale DNS errors"
