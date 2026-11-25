#!/usr/bin/env bash
# Start ShopLite locally from images shop-<service>:$TAG.
# Usage: ./scripts/up.sh            (TAG defaults to 1.0.0)
#        TAG=1.0.1 SERVER_NAME=shoplite.test ./scripts/up.sh
# Safe to run again: containers are recreated, networks and the pgdata volume are kept.
set -euo pipefail

cd "$(dirname "$0")/.."

TAG="${TAG:-1.0.0}"
SERVER_NAME="${SERVER_NAME:-shoplite.test}"

FRONTEND_IMAGE="shop-frontend:$TAG"
CATALOG_IMAGE="shop-catalog:$TAG"
INVENTORY_IMAGE="shop-inventory:$TAG"
ORDERS_IMAGE="shop-orders:$TAG"

if [ ! -f .env ]; then
  echo ".env not found in $(pwd). Copy .env.example to .env and set the values." >&2
  exit 1
fi
if [ ! -f db/init.sql ]; then
  echo "db/init.sql not found in $(pwd)" >&2
  exit 1
fi

for image in "$FRONTEND_IMAGE" "$CATALOG_IMAGE" "$INVENTORY_IMAGE" "$ORDERS_IMAGE"; do
  if ! docker image inspect "$image" >/dev/null 2>&1; then
    echo "Image $image not found locally. Build it first." >&2
    exit 1
  fi
done

# Print the last 20 log lines of a container (used when something fails).
show_logs() {
  echo "---- last 20 log lines of $1 ----" >&2
  docker logs --tail 20 "$1" >&2 || true
}

# Networks and volume: create only if missing.
docker network inspect frontend-net >/dev/null 2>&1 || docker network create frontend-net >/dev/null
docker network inspect backend-net >/dev/null 2>&1 || docker network create --internal backend-net >/dev/null
docker volume inspect pgdata >/dev/null 2>&1 || docker volume create pgdata >/dev/null

# Tier 1: Postgres (backend-net only, no published port).
echo "==> Starting postgres"
docker rm -f postgres >/dev/null 2>&1 || true
docker run -d --name postgres --restart unless-stopped \
  --network backend-net \
  --env-file .env \
  -v pgdata:/var/lib/postgresql/data \
  -v "$(pwd)/db/init.sql:/docker-entrypoint-initdb.d/init.sql:ro" \
  --health-cmd 'pg_isready -U "$POSTGRES_USER" -d "$POSTGRES_DB"' \
  --health-interval 5s --health-timeout 3s --health-retries 12 \
  postgres:17-alpine >/dev/null

echo "==> Waiting for postgres to be healthy (max 60 s)"
status="none"
for _ in $(seq 1 30); do
  status="$(docker inspect -f '{{.State.Health.Status}}' postgres 2>/dev/null || echo none)"
  [ "$status" = "healthy" ] && break
  sleep 2
done
if [ "$status" != "healthy" ]; then
  echo "postgres did not become healthy within 60 seconds" >&2
  show_logs postgres
  exit 1
fi
echo "    postgres is healthy"

# Wait until a URL answers on backend-net (uses the frontend image, it has wget).
wait_http() {
  local name="$1" url="$2"
  echo "==> Waiting for $name at $url (max 60 s)"
  for _ in $(seq 1 30); do
    if docker run --rm --network backend-net --entrypoint wget "$FRONTEND_IMAGE" \
         -q -O /dev/null -T 3 "$url" >/dev/null 2>&1; then
      echo "    $name is up"
      return 0
    fi
    sleep 2
  done
  echo "$name did not answer within 60 seconds" >&2
  show_logs "$name"
  return 1
}

# Tier 2: backends (backend-net only, no published port).
start_backend() {
  local name="$1" image="$2"
  echo "==> Starting $name"
  docker rm -f "$name" >/dev/null 2>&1 || true
  docker run -d --name "$name" --restart unless-stopped \
    --network backend-net \
    --env-file .env \
    "$image" >/dev/null
}

start_backend catalog "$CATALOG_IMAGE"
start_backend inventory "$INVENTORY_IMAGE"
start_backend orders "$ORDERS_IMAGE"
wait_http catalog http://catalog:3000/health
wait_http inventory http://inventory:8081/health
wait_http orders http://orders:8082/health

# Tier 3: frontend. Created, joined to backend-net, then started,
# so nginx can resolve the backend names at startup.
echo "==> Starting frontend"
docker rm -f frontend >/dev/null 2>&1 || true
docker create --name frontend --restart unless-stopped \
  --network frontend-net \
  -p 80:80 \
  -e "SERVER_NAME=$SERVER_NAME" \
  "$FRONTEND_IMAGE" >/dev/null
docker network connect backend-net frontend
docker start frontend >/dev/null

echo "==> Checking /api/catalog/health through nginx (Host: $SERVER_NAME, max 60 s)"
for _ in $(seq 1 30); do
  if curl -fsS --max-time 3 -H "Host: $SERVER_NAME" http://127.0.0.1/api/catalog/health >/dev/null 2>&1; then
    echo "==> ShopLite is up: http://$SERVER_NAME"
    exit 0
  fi
  sleep 2
done

echo "Frontend did not answer within 60 seconds" >&2
show_logs frontend
exit 1