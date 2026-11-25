# ShopLite (Team Robin)

## Team workflow
- Nobody pushes directly to `main`.
- One branch per Jira ticket, named like `SHOP-12-inventory-service`.
- Every change goes through a pull request approved by a teammate before merging.
- No secrets in Git, images, workflow files or Slack.
- Review rotation: Abdul Waris reviews Israr, Israr reviews Abdul Waris.

## Architecture

```
browser -> frontend (nginx, port 80, the only published port)
            +-> catalog   (Node.js, 3000)
            +-> inventory (Go, 8081)
            +-> orders    (Spring Boot, 8082)
                   +-> postgres (17-alpine, 5432, volume pgdata)
backend services and postgres are on backend-net (--internal) only
```

## Run locally

Needs Docker, a .env file (copy .env.example) and the hosts entry `127.0.0.1 shoplite.test`. Build the images as `shop-<service>:1.0.0`, then:

```
./scripts/up.sh            # start everything (TAG=1.0.0 by default)
./scripts/down.sh          # stop, keep the pgdata volume
./scripts/down.sh --purge  # stop and delete the data
```

Test results: docs/evidence/phase1-tests.md

## Deploy

Every merge to main runs deploy.yml: OIDC login to AWS (no stored keys), build of the 4 images, push to ECR tagged with the short commit SHA, deploy over SSH with /opt/shoplite/deploy.sh, then a smoke test. Pull requests run ci.yml (hadolint, build, size budget). Live site: http://shoplite-robin.duckdns.org

## Roll back

On the VM, run an older commit SHA (latest is refused):

```
IMAGE_TAG=<older-sha> /opt/shoplite/deploy.sh
```

## ECR setup

```
aws ecr create-repository --region ap-southeast-2 --repository-name shoplite/<service> --image-tag-mutability IMMUTABLE --image-scanning-configuration scanOnPush=true
aws ecr put-lifecycle-policy --region ap-southeast-2 --repository-name shoplite/<service> --lifecycle-policy-text file://lifecycle.json
```

lifecycle.json keeps the last 10 images (rule: tagStatus any, countType imageCountMoreThan, countNumber 10, action expire). Services: frontend, catalog, inventory, orders.

## Notes and differences from the brief

- Region is ap-southeast-2 (Sydney), not ap-south-1: an organization policy denied ECR creation in Mumbai.
- The VM runs Ubuntu 26.04 instead of 24.04.
- Production uses the volume shoplite-pgdata; up.sh and down.sh use pgdata as in the brief.
- Hadolint ignore DL3018 (inventory Dockerfile): apk add ca-certificates is not version-pinned, because Alpine package versions change with the base image.
