# compralatino-infra

Local dev infrastructure for CompraLatino. For now this is plain Docker
Compose; Helm charts for the K3s cluster (see Fase-2-CompraLatino-Mermaid.md
2.5) will be added here later.

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

# Everything, infra + all services (note: backend services depend_on the
# infra services, so their profile must be active too — use `all` rather
# than `services` alone unless infra is already running elsewhere)
docker compose -f compose.yaml -f compose.services.yaml --profile all up -d --build
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
