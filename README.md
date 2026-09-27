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

There is no API Gateway container here — routing between services is
deferred to the Kubernetes/Helm setup.

## Usage

```bash
cp .env.example .env   # first time only; defaults are fine for local dev

# Shared infra only (useful when iterating on one service outside Docker)
docker compose up -d

# Everything, infra + all services
docker compose -f compose.yaml -f compose.services.yaml up -d --build
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
