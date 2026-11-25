#!/usr/bin/env bash
# Stop and remove ShopLite containers and networks.
# Usage: ./scripts/down.sh            keeps the pgdata volume (data survives)
#        ./scripts/down.sh --purge    also deletes the pgdata volume (data is lost)
set -euo pipefail

PURGE=0
case "${1:-}" in
  "") ;;
  --purge) PURGE=1 ;;
  *) echo "Usage: $0 [--purge]" >&2; exit 1 ;;
esac

echo "==> Removing containers"
for name in frontend orders inventory catalog postgres; do
  docker rm -f "$name" >/dev/null 2>&1 || true
done

echo "==> Removing networks"
for net in frontend-net backend-net; do
  docker network rm "$net" >/dev/null 2>&1 || true
done

if [ "$PURGE" -eq 1 ]; then
  echo "==> Removing volume pgdata (--purge)"
  docker volume rm pgdata >/dev/null 2>&1 || true
else
  echo "==> Keeping volume pgdata (use --purge to delete it)"
fi

echo "==> ShopLite is down"