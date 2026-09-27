-- One schema per microservice, sharing a single PostgreSQL instance/database.
-- See Fase-2-CompraLatino-Mermaid.md 2.3: each service owns its schema and
-- never accesses another service's tables directly.
CREATE SCHEMA IF NOT EXISTS users_svc;
CREATE SCHEMA IF NOT EXISTS catalog_svc;
CREATE SCHEMA IF NOT EXISTS orders_svc;
CREATE SCHEMA IF NOT EXISTS recommendations_svc;
CREATE SCHEMA IF NOT EXISTS admin_svc;
CREATE SCHEMA IF NOT EXISTS yauctions_svc;
