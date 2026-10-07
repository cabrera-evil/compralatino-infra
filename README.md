# compralatino-infra

Local dev infrastructure for CompraLatino. Docker Compose
for local work and Helm values (chart `cabrera-evil/deploy-chart`) for the K3s
cluster (see Fase-2-CompraLatino-Mermaid.md 2.5).

## Layout

- `compose.yaml` — shared infra: PostgreSQL (single instance, one
  schema per service — see `init-db/`), Redis (cache/queues), RabbitMQ
  (inter-service pub/sub, with the management UI on 15672).
- `compose.services.yaml` — all backend services and the frontend,
  each built from its sibling repo directory. Requires this repo to be
  cloned next to the service repos:

  ```
  git/udb/dse/
    compralatino-infra/
    compralatino-users-api/
    compralatino-catalog-api/
    compralatino-orders-api/
    compralatino-recommendations-api/
    compralatino-admin-api/
    compralatino-yauctions-api/
    compralatino-frontend/
  ```
- `helm/values/` — one values file per release (six APIs + frontend), with
  the Traefik `Ingress` routing by path under `/api/v1`.
- `helm/secrets/` — per-release secret values (gitignored, `CHANGE_ME`
  placeholders until filled in).
- `init-db/` — SQL run once on first Postgres startup to create the
  per-service schemas.

## Gateway (Traefik)

Traefik (profile `gateway`, also in `infra` and `all`) stands in for the
production Kubernetes ingress. Routers are declared as labels on each
service in `compose.services.yaml`. Every API serves `/api/v1/...` itself, so
the gateway routes by resource path under `/api/v1` with no prefix stripping.
The legacy per-service `/<svc>/...` routers (prefix stripped) remain for
debugging and health checks.

| URL | Target |
| --- | --- |
| `http://localhost/` | frontend |
| `http://api.localhost/api/v1/{auth,user,role,permissions,api-key,audit-log}` | users-api |
| `http://api.localhost/api/v1/{products,categories}` | catalog-api |
| `http://api.localhost/api/v1/{orders,cart,checkout-options}` | orders-api (reserved) |
| `http://api.localhost/api/v1/recommendations` | recommendations-api (reserved) |
| `http://api.localhost/api/v1/yauctions` | yauctions-api (reserved) |
| `http://api.localhost/api/v1/admin` | admin-api (reserved) |
| `http://api.localhost/<svc>/api/health` | per-service debug/health (`users`, `catalog`, `orders`, `recommendations`, `admin`, `yauctions`) |
| `http://localhost:8080` | Traefik dashboard (dev only, bound to 127.0.0.1) |

Reserved routes return 404 until the service implements them. `*.localhost`
resolves to 127.0.0.1 without editing `/etc/hosts`. Change the host port with
`GATEWAY_PORT` if 80 is taken. In Docker the frontend gets
`NEXT_PUBLIC_API_URL=http://traefik/api/v1`, `NEXT_PUBLIC_PROXY=true` and
`NEXT_PUBLIC_HOST` (`FRONTEND_ORIGIN`, default `http://localhost`); its `/api/*`
rewrite targets that URL.

Host dev (frontend run on the host, gateway in Docker): set
`NEXT_PUBLIC_API_URL=http://api.localhost/api/v1` in the frontend `.env`.

## Usage

Every service is gated behind Compose [profiles](https://docs.docker.com/compose/how-tos/profiles/),
so nothing starts unless you pass `--profile`. Each service has its own
profile (matching its name), plus group profiles: `infra` (postgres, redis,
rabbitmq), `services` (all backend APIs + frontend), and `all` (everything).

```bash
cp .env.example .env   # first time only; defaults are fine for local dev

# Just one piece of shared infra, e.g. when the rest runs on another cluster
docker compose --profile rabbitmq up -d

# All shared infra
docker compose --profile infra up -d

# Everything, infra + all services (dependencies on infra are optional, so
# `--profile services` alone also loads; `all` keeps start order and health waits)
docker compose -f compose.yaml -f compose.services.yaml --profile all up -d --build

# Build a single service without any profile
docker compose -f compose.yaml -f compose.services.yaml build users-api
```

Each service's own `.env` (in its sibling repo) is loaded via `env_file` for
its app-level secrets (JWT, SMTP, Cloudinary, Google OAuth, etc.); this repo
only overrides the values that must point at the Docker network instead of
`localhost` or the cloud DB (`DATABASE_URL`, `REDIS_HOST`, `RABBITMQ_URL`,
`RABBITMQ_QUEUE`, `PORT`).

Host ports: users-api `3001`, catalog-api `3002`, orders-api `3003`,
recommendations-api `3004`, admin-api `3005`, yauctions-api `3006`,
frontend `3000`. RabbitMQ management UI: `15672`.

## First run

The Postgres volume starts empty — `init-db/001-init-schemas.sql` creates
the schemas, but each service's own Prisma migrations still need to run
against this local database:

```bash
# from each backend service's repo, pointed at the local Docker Postgres
DATABASE_URL="postgresql://compralatino:compralatino@localhost:5432/compralatino?schema=<svc>_svc" \
  npx prisma migrate deploy --schema=prisma/schema.prisma
```

## Kubernetes (Helm)

Each service is a release of
[`cabrera-evil/deploy-chart`](https://artifacthub.io/packages/helm/cabrera-evil-charts/deploy-chart)
(0.3.0) in the `compralatino` namespace. Traefik, as the cluster ingress
controller (`className: traefik`), is the gateway: APIs are served on
`api.compralatino.example.com` under `/api/v1/<resource>` and the frontend on
`compralatino.example.com`. TLS uses cert-manager (`letsencrypt-production`).
Replace both hosts with the real ones in `helm/values/*.yaml`.

Prerequisites: Traefik, cert-manager and the Postgres, Redis and RabbitMQ
services (`postgres`, `redis`, `rabbitmq`) in the same namespace. Infra is not
part of these values.

```bash
helm repo add cabrera-evil https://cabrera-evil.github.io/charts/
helm repo update
```

Secrets live in `helm/secrets/<release>.yaml` (gitignored). Replace every
`CHANGE_ME` before deploying. `NEXT_PUBLIC_*` values are inlined when the
frontend image is built, so set them as build args there too.

Deploy one release (tag defaults to `latest`):

```bash
helm upgrade --install users-api cabrera-evil/deploy-chart --version 0.3.0 \
  -n compralatino --create-namespace \
  -f helm/values/users-api.yaml -f helm/secrets/users-api.yaml \
  --set image.tag=<tag>
```

Releases: `users-api`, `catalog-api`, `orders-api`, `recommendations-api`,
`admin-api`, `yauctions-api`, `frontend`.

### Compile everything into a single YAML

Renders every release into `helm/compiled.yaml` (gitignored, it embeds the
secrets), ready to apply:

```bash
for f in helm/values/*.yaml; do
  n=$(basename "$f" .yaml)
  helm template "$n" cabrera-evil/deploy-chart --version 0.3.0 --skip-tests \
    -n compralatino -f "$f" -f "helm/secrets/$n.yaml"
  echo '---'
done > helm/compiled.yaml

kubectl create namespace compralatino --dry-run=client -o yaml | kubectl apply -f -
kubectl apply -n compralatino -f helm/compiled.yaml
```

### Compile a single service

Renders one release into `helm/compiled-<release>.yaml` (gitignored, it embeds
that service's secrets). Set `SVC` to any release name:

```bash
SVC=users-api
tag=latest   # image tag to deploy

helm template "$SVC" cabrera-evil/deploy-chart --version 0.3.0 --skip-tests \
  -n compralatino --set image.tag="$tag" \
  -f "helm/values/$SVC.yaml" -f "helm/secrets/$SVC.yaml" > "helm/compiled-$SVC.yaml"

kubectl apply -n compralatino -f "helm/compiled-$SVC.yaml"
```
