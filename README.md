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
service in `compose.services.yaml`. Every API serves `/api/v1/...`, so each
one is exposed under its own prefix, which Traefik strips:

| URL | Target |
| --- | --- |
| `http://localhost/` | frontend |
| `http://api.localhost/users/api/v1/...` | users-api |
| `http://api.localhost/catalog/...`, `/orders/...`, `/recommendations/...`, `/admin/...`, `/yauctions/...` | matching API |
| `http://localhost:8080` | Traefik dashboard (dev only, bound to 127.0.0.1) |

`*.localhost` resolves to 127.0.0.1 without editing `/etc/hosts`. Change the
host port with `GATEWAY_PORT` if 80 is taken. The frontend proxies `/api/*`
to `http://traefik` over the Docker network.

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
