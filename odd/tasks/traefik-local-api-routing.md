# Local Traefik API Routing

## Objective
Run APIs either as Docker services or local `pnpm` development processes while retaining one Dockerized Traefik gateway.

## Problem
Docker-provider labels discover only containers. Local API processes need a file-provider route, but identical live routes for both targets would make selection ambiguous.

## Scope
- Add file-provider support to the shared Traefik service.
- Add a local-only Compose overlay and host-targeted dynamic routes.
- Preserve existing Docker DNS/service-label routing unchanged.

## Constraints
- Modes are explicit and mutually exclusive for API routing.
- Use `host.docker.internal:host-gateway` for Docker-to-host access on Linux.
- No new dependencies.

## Delivery
- Strategy: ask-on-risk
- Forecast: under 100 authored changed lines; one work unit.

## Tasks
- [x] T1 — Add local Traefik provider and Compose overlay. Route: delegated; trigger: three non-trivial configuration files. Acceptance: local mode disables the Docker provider and routes host APIs through the file provider; Docker mode retains its existing labels.

## Progress
- Verification: `docker compose -f compose.yaml -f compose.local.yaml config` — passed (exit 0); `docker compose -f compose.yaml -f compose.services.yaml --profile infra --profile services config` — passed (exit 0); `git diff --check` — passed (exit 0).
- Local mode invocation: `docker compose -f compose.yaml -f compose.local.yaml --profile gateway up -d`.
- No automated test applies to this declarative routing change; no containers were started.
- Work-unit commit: `ebb9034` (`feat(infra): add local Traefik API routing`). Authored line count: 176 additions.
- Next: Run the receipt-driven review lifecycle for this work unit, then decide whether to push or open a PR.
