#!/usr/bin/env bash
# Deploy one image tag of ShopLite on the VM.
# Usage (on the VM): IMAGE_TAG=<short-sha> /opt/shoplite/deploy.sh
# Rollback: run it again with an older IMAGE_TAG.
set -euo pipefail

cd "$(dirname "$0")"

if [ -z "${IMAGE_TAG:-}" ]; then
  echo "IMAGE_TAG is required, for example: IMAGE_TAG=abc1234 $0" >&2
  exit 1
fi
if [ "$IMAGE_TAG" = "latest" ]; then
  echo "Refusing to deploy 'latest'. Use a commit SHA." >&2
  exit 1
fi
if [ ! -f .env ]; then
  echo ".env not found in $(pwd)" >&2
  exit 1
fi

REGION="${AWS_REGION:-ap-southeast-2}"
ACCOUNT_ID="$(aws sts get-caller-identity --query Account --output text)"
REGISTRY="${ACCOUNT_ID}.dkr.ecr.${REGION}.amazonaws.com"

FRONTEND_IMAGE="$REGISTRY/shoplite/frontend:$IMAGE_TAG"
CATALOG_IMAGE="$REGISTRY/shoplite/catalog:$IMAGE_TAG"
INVENTORY_IMAGE="$REGISTRY/shoplite/inventory:$IMAGE_TAG"
ORDERS_IMAGE="$REGISTRY/shoplite/orders:$IMAGE_TAG"

echo "Deploying tag $IMAGE_TAG from $REGISTRY"
aws ecr get-login-password --region "$REGION" | docker login --username AWS --password-stdin "$REGISTRY"

# Pull everything first: a wrong tag fails here, before anything is stopped.
for image in "$FRONTEND_IMAGE" "$CATALOG_IMAGE" "$INVENTORY_IMAGE" "$ORDERS_IMAGE"; do
  echo "==> Pulling $image"
  docker pull "$image"
done

# Networks (created once, kept between deploys).
docker network inspect frontend-net >/dev/null 2>&1 || docker network create frontend-net
docker network inspect backend-net >/dev/null 2>&1 || docker network create --internal backend-net

# Postgres: leave it alone if it is already running.
pg_running="$(docker inspect -f '{{.State.Running}}' postgres 2>/dev/null || echo missing)"
if [ "$pg_running" = "true" ]; then
  echo "==> postgres already running, leaving it"
elif [ "$pg_running" = "false" ]; then
  echo "==> Starting existing postgres container"
  docker start postgres
else
  echo "==> Creating postgres"
  docker run -d --name postgres --restart unless-stopped \
    --network backend-net \
    --env-file .env \
    -v shoplite-pgdata:/var/lib/postgresql/data \
    -v "$(pwd)/db/init.sql:/docker-entrypoint-initdb.d/init.sql:ro" \
    --health-cmd 'pg_isready -U "$POSTGRES_USER" -d "$POSTGRES_DB"' \
    --health-interval 5s --health-timeout 3s --health-retries 12 \
    postgres:17-alpine
fi

echo "==> Waiting for postgres to be healthy"
for _ in $(seq 1 30); do
  status="$(docker inspect -f '{{.State.Health.Status}}' postgres 2>/dev/null || echo none)"
  [ "$status" = "healthy" ] && break
  sleep 2
done
if [ "$status" != "healthy" ]; then
  echo "postgres did not become healthy" >&2
  exit 1
fi

# Wait until a URL answers on backend-net. Uses the frontend image (alpine, has wget).
wait_http() {
  local name="$1" url="$2"
  echo "==> Waiting for $name at $url"
  for _ in $(seq 1 30); do
    if docker run --rm --network backend-net --entrypoint wget "$FRONTEND_IMAGE" \
         -q -O /dev/null -T 3 "$url" >/dev/null 2>&1; then
      echo "    $name is up"
      return 0
    fi
    sleep 2
  done
  echo "$name did not answer in time" >&2
  return 1
}

# Replace one backend: remove the old container, start the new one on backend-net only.
start_backend() {
  local name="$1" image="$2"
  echo "==> Replacing $name"
  docker rm -f "$name" >/dev/null 2>&1 || true
  docker run -d --name "$name" --restart unless-stopped \
    --network backend-net \
    --env-file .env \
    "$image"
}

start_backend catalog "$CATALOG_IMAGE"
wait_http catalog http://catalog:3000/health

start_backend inventory "$INVENTORY_IMAGE"
wait_http inventory http://inventory:8081/health

start_backend orders "$ORDERS_IMAGE"
wait_http orders http://orders:8082/health

# Frontend last: nginx resolves backend names at start, so it must start after them.
# It is created, joined to backend-net, then started, so the names resolve at startup.
echo "==> Replacing frontend"
docker rm -f frontend >/dev/null 2>&1 || true
docker create --name frontend --restart unless-stopped \
  --network frontend-net \
  -p 80:80 \
  --env-file .env \
  "$FRONTEND_IMAGE" >/dev/null
docker network connect backend-net frontend
docker start frontend >/dev/null

# Final check through nginx, up to 60 seconds.
SERVER_NAME="$(grep -E '^SERVER_NAME=' .env | head -n 1 | cut -d= -f2-)"
echo "==> Checking /api/catalog/health through nginx (Host: $SERVER_NAME)"
for _ in $(seq 1 30); do
  if curl -fsS --max-time 3 -H "Host: $SERVER_NAME" http://127.0.0.1/api/catalog/health >/dev/null 2>&1; then
    echo "==> Healthy. Tag $IMAGE_TAG is live."
    docker image prune -af --filter "until=168h" >/dev/null
    exit 0
  fi
  sleep 2
done

echo "Deploy failed: /api/catalog/health did not answer within 60 seconds" >&2
exit 1