# Phase 2 evidence

Date: 2026-11-25. Live site: http://shoplite-robin.duckdns.org (VM Elastic IP 3.104.255.35).

## Notes that differ from the brief

- **Region:** everything runs in ap-southeast-2 (Sydney). Creating ECR repositories in ap-south-1 (Mumbai) was denied by an organization service control policy, and the VM is in Sydney.
- **VM:** Ubuntu 26.04, instance type t3.small (2 GiB memory) with a 2 GiB swap file. The Java service froze a smaller instance (t3.micro) during its first start, so it was resized.
- **Hadolint:** `inventory-service/Dockerfile` ignores rule DL3018 (pin versions in `apk add`) on the `ca-certificates` line. Reason: Alpine removes old package versions from its repository, so a pinned version would break the build later.
- **Scripts:** `scripts/deploy.sh` was written from the brief and the app code.

## Registry and authentication

- Four private ECR repositories: `shoplite/frontend`, `shoplite/catalog`, `shoplite/inventory`, `shoplite/orders`. Tags are immutable, scan on push is on, lifecycle policy keeps the last 10 images.
- Images are tagged with the 7-character git commit SHA (latest deployed: `7f9b39a`). `latest` is never deployed: `deploy.sh` refuses it.
- GitHub Actions logs in to AWS with OIDC (role `shoplite-github-actions`, trusted only for this repository on `main`, allowed to push only to the four repositories). The VM pulls with its instance role `shoplite-ec2-role` (pull only). No AWS access keys are stored anywhere.
- ECR scan findings: see the section 'ECR scan results' below.

## Pipelines

- `ci.yml` runs on pull requests and on pushes to `main`: hadolint on the four Dockerfiles, a docker build of the four images, and a size budget check (frontend 60 MB, catalog 200 MB, inventory 30 MB, orders 300 MB). All 8 jobs were green on PR #4 and on the nginx change.
- `deploy.yml` runs on a push to `main` or manually: it builds and pushes the four images tagged with the commit SHA, then deploys over SSH with `scripts/deploy.sh` and runs a smoke test on `/api/catalog/health` at the domain. The run after merging the nginx change was green.

## VM checks

SSH is key-only (output of `sshd -T`):

    permitrootlogin prohibit-password
    pubkeyauthentication yes
    passwordauthentication no
    kbdinteractiveauthentication no

Only ports 22 and 80 listen publicly (`sudo ss -tlnp`; the 127.0.0.53 and 127.0.0.54 lines are the VM's local DNS). Only the frontend publishes a port (`docker ps`: `frontend 0.0.0.0:80->80/tcp`; postgres, catalog, inventory and orders show only internal ports).

## Tests from my laptop

| Command | Result |
| --- | --- |
| `curl -i http://shoplite-robin.duckdns.org/api/catalog/health` | 200 OK, `{"status":"ok"}` |
| `curl -i http://3.104.255.35` (bare IP) | Empty reply from server (nginx default server returns 444) |
| `curl http://3.104.255.35:3000` | Connection timed out |
| Browser at `http://shoplite-robin.duckdns.org` | Product list appears |

## Rollback

`IMAGE_TAG=<older-sha> /opt/shoplite/deploy.sh` on the VM redeploys any tag that is still in ECR. It pulls all four images first, so a wrong tag fails before anything is stopped. This was run by hand with tag `7f9b39a` and ended with `Healthy. Tag 7f9b39a is live.`

## VM checks (2026-11-25)

SSH accepts keys only:

    $ sudo sshd -T | grep -i passwordauthentication
    passwordauthentication no

Listening ports. Only 22 and 80 are reachable from outside; the 127.0.0.x entries on port 53 are the VM's local DNS resolver:

    $ sudo ss -tlnp
    LISTEN 0.0.0.0:22     sshd
    LISTEN 0.0.0.0:80     docker-proxy
    LISTEN [::]:22        sshd
    LISTEN [::]:80        docker-proxy
    LISTEN 127.0.0.53:53  systemd-resolve (local only)
    LISTEN 127.0.0.54:53  systemd-resolve (local only)

From my laptop:

    $ curl.exe -v http://3.104.255.35
    curl: (52) Empty reply from server
    $ curl.exe -v -m 5 http://3.104.255.35:3000
    curl: (28) Connection timed out after 5012 milliseconds
    $ curl.exe -s -o NUL -w "%{http_code}" http://shoplite-robin.duckdns.org/api/catalog/health
    200

## ECR scan results (image tag fb533ac, region ap-southeast-2)

Scan on push is enabled. The earlier tags were OCI image indexes, which ECR cannot scan (UnsupportedImageTypeException). Since SHOP-11 the images are built with --provenance=false --sbom=false and are scanned.

| Repository | Critical | High | Medium |
|---|---|---|---|
| shoplite/frontend | 1 | 0 | 0 |
| shoplite/catalog | 1 | 4 | 1 |
| shoplite/inventory | 1 | 4 | 1 |
| shoplite/orders | 0 | 1 | 0 |

All three critical findings are the same one: CVE-2026-4738 in the Alpine package zlib 1.3.2-r1. A fix has not been applied yet.