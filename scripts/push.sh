#!/usr/bin/env bash
# Build, tag and push all ShopLite images to ECR.
# Usage: ./scripts/push.sh
set -euo pipefail

REGION="${AWS_REGION:-ap-southeast-2}"

if [ -n "$(git status --porcelain)" ]; then
  echo "Commit your changes first: the image tag is the commit SHA." >&2
  exit 1
fi

TAG="$(git rev-parse --short HEAD)"
ACCOUNT_ID="$(aws sts get-caller-identity --query Account --output text)"
REGISTRY="${ACCOUNT_ID}.dkr.ecr.${REGION}.amazonaws.com"

# ECR name : source folder
SERVICES=("frontend:frontend" "catalog:catalog-service" "inventory:inventory-service" "orders:order-service")

echo "Registry: $REGISTRY  Tag: $TAG"
aws ecr get-login-password --region "$REGION" | docker login --username AWS --password-stdin "$REGISTRY"

for entry in "${SERVICES[@]}"; do
  name="${entry%%:*}"
  dir="${entry##*:}"
  image="$REGISTRY/shoplite/$name:$TAG"
  echo "==> Building $image"
  docker build --platform linux/amd64 -t "$image" "$dir"
  echo "==> Pushing $image"
  docker push "$image"
done

echo "Done. Pushed tag $TAG for all four images."
