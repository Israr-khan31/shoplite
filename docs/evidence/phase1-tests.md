# Phase 1 tests (25 Nov 2026)

Run on the VM (no Docker Desktop on the laptop) with ./scripts/up.sh. Images were the production images (tag 1147735) retagged as shop-SERVICE:1.0.0. Volume pgdata; the production volume shoplite-pgdata was not touched.

| # | Test | Output | Result |
|---|---|---|---|
| 1 | curl -I http://shoplite.test | HTTP/1.1 200 OK | PASS |
| 2 | curl /api/catalog/products | 3 products (Keyboard, Mouse, Monitor) | PASS |
| 3 | POST /api/orders/orders productId 1 quantity 2 | 201, stock of product 1 went 20 to 18 | PASS |
| 4 | curl localhost 3000, 8081, 8082; docker ps | all refused (exit 7); only frontend shows 0.0.0.0:80->80 | PASS |
| 5 | busybox wget http://postgres:5432 from frontend-net | wget: bad address | PASS |
| 6 | busybox wget http://catalog:3000/health from backend-net | status ok | PASS |
| 7 | docker exec postgres wget https://example.com | wget: bad address | PASS |
| 8 | down.sh then up.sh | order still there, stock 18 | PASS |
| 9 | down.sh --purge then up.sh | orders empty, stock 20 | PASS |

## Networks

frontend-net internal=false containers=frontend

backend-net internal=true containers=inventory frontend postgres orders catalog

## Image sizes (over budget, fixed in the Dockerfile work)

| Image | Size | Budget |
|---|---|---|
| frontend | 103 MB | 60 MB |
| catalog | 252 MB | 200 MB |
| inventory | 38 MB | 30 MB |
| orders | 524 MB | 300 MB |
