# PACT — Canonical Contract Artifacts

Machine-readable contracts for PACT, generated directly from the PACT
documentation set. These are the artifacts an engineering team would otherwise
hand-write first; they are derived strictly from **PACT Engineering Foundations**
(the source of truth) and the **Product Architecture & Build Specification**, so
there is a single canonical schema expressed in three forms — no drift.

## Files

| File | What it is | Source in the docs |
|------|------------|--------------------|
| `pact_v1.proto` | Protobuf 3 — the hot-path contract: `ActionContext`, `Decision`, `AuditEntry`, all enums, and the `EnforcementGateway` (`EvaluateAction` / `StreamSession`) and `PolicyEngine` (`EvaluatePolicy`) gRPC services. | Foundations §2 (data contracts), §3 (API surface); Product Spec §5, §20 |
| `pact_openapi.yaml` | OpenAPI 3.1 — the REST control-plane surface: sessions, policies, audit/compliance, tenants, billing. Includes the §4 error envelope. | Foundations §3, §4; Product Spec §20 |
| `pact_schema.sql` | PostgreSQL DDL — the control-plane schema (10 entities), with tenant-isolation RLS (I5) and an append-only, hash-chained audit log. | Foundations §2 (entities); Product Spec §10 (Data Model) |

## How they relate to the system

- **Hot path is gRPC** (`pact_v1.proto`) — `EvaluateAction` is the per-action
  call the Enforcement Gateway (component 01) serves. The proto *is* the schema
  referenced by Foundations §3.
- **Management is REST** (`pact_openapi.yaml`) — session lifecycle (Orchestrator
  10), policy authoring (12), audit/compliance (08), tenants (09), billing (15).
- **Control-plane state is Postgres** (`pact_schema.sql`). Note what is **not**
  here, by design:
  - Per-session **runtime** state → fast session store (e.g. Redis), not this DB.
  - Policy **rules / entity data** → live only in enclaves (invariant I1); never
    persisted in plaintext here.
  - Memory **content** → the memory backend; only governed *metadata* is stored.

## Invariants encoded in the artifacts

- **Fail-closed** (combination notes in `pact_v1.proto`): `final = ALLOW iff every
  invoked party ALLOWs`; any DENY/error/timeout ⇒ DENY.
- **Isolation** I1 (policy never leaves the enclave; only `Decision` crosses),
  I2/I3 (combination is constant-time, symmetric-denial — `policy_rule` is audit
  only), I5 (tenant-isolation RLS in the DDL), I6 (memory origin metadata).
- **Audit integrity**: `entry_hash = sha256(prev_hash + canonical(body))`;
  the `audit_entry` table is append-only (UPDATE/DELETE blocked by trigger) and
  uniqueness on `(session_id, sequence_no)` gives replay protection.

## Validation

All three validate against real tooling:
- `pact_v1.proto` — compiles with `protoc` (uses well-known types `timestamp`,
  `struct`).
- `pact_openapi.yaml` — parses as OpenAPI 3.1; all `$ref`s resolve.
- `pact_schema.sql` — parses against the PostgreSQL grammar (10 tables, 7 enums,
  7 RLS policies, append-only audit trigger).

## Source of truth

If a contract changes, change it in **Engineering Foundations** first, then
regenerate these. The 18 component design documents reference Foundations (they
never redefine the contracts), so the whole set stays consistent.

## Suggested repo layout

```
proto/pact/v1/pact.proto      <- pact_v1.proto
api/openapi.yaml              <- pact_openapi.yaml
db/migrations/0001_init.sql   <- pact_schema.sql
```

Generate language stubs from the proto (Rust on the hot path; the SDK languages
— at minimum Python and TypeScript — for client generation) and from the OpenAPI
spec, per Product Spec §20.3.
