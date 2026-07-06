-- ============================================================================
--  PACT — Control-Plane Schema (PostgreSQL)
--  pact_schema.sql
--
--  Machine-readable form of the data model in PACT Engineering Foundations
--  (entities) and Product Spec §10 (Data Model & Persistence). Foundations and
--  the product spec are the source of truth; this DDL formalizes the
--  control-plane persistence.
--
--  Scope: control-plane state of record (tenants, members, agent identities,
--  policy bundles, constitutions, sessions, participants) and the audit log.
--  NOT in scope here: per-session runtime state (lives in a fast session store,
--  e.g. Redis — Foundations §9), policy *contents*/entity data (live only in
--  enclaves — Foundations I1), and memory *content* (lives in the memory
--  backend — only governed metadata is persisted, Product Spec §8.5).
--
--  Invariants encoded:
--    I5  Tenant isolation — every tenant-owned table carries tenant_id and is
--        protected by Row-Level Security (RLS). This is the FLOOR; single-tenant
--        and high-assurance deployments use schema- or database-per-tenant
--        (Product Spec §10.2 / §11.1).
--    Audit — the audit log is append-only and hash-chained; UPDATE/DELETE are
--        revoked and a trigger forbids mutation. Mirrored to WORM out of band.
--    Versioning — policies and constitutions are versioned; a session pins the
--        versions it began with (Foundations §7).
-- ============================================================================

BEGIN;

CREATE EXTENSION IF NOT EXISTS "uuid-ossp";

-- Enum types mirror Foundations §2.1 / pact_v1.proto -------------------------
CREATE TYPE participation_mode AS ENUM ('bilateral', 'proxy');
CREATE TYPE session_state      AS ENUM ('initiating', 'active', 'suspended', 'closed');
CREATE TYPE verdict            AS ENUM ('ALLOW', 'DENY');
CREATE TYPE memory_effect      AS ENUM ('none', 'session_scoped', 'persisted');
CREATE TYPE region             AS ENUM ('us', 'eu');
CREATE TYPE agent_status       AS ENUM ('active', 'revoked');
CREATE TYPE constitution_status AS ENUM ('draft', 'active', 'suspended', 'closed');

-- ----------------------------------------------------------------------------
--  TENANT (Organization) — root of multi-tenancy
-- ----------------------------------------------------------------------------
CREATE TABLE tenant (
    tenant_id       UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    name            TEXT NOT NULL,
    identity_domain TEXT NOT NULL UNIQUE,
    entitlements    JSONB NOT NULL DEFAULT '{}'::jsonb,
    region          region NOT NULL,
    created_at      TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- ----------------------------------------------------------------------------
--  MEMBER — tenant users (linked to enterprise IdP via SSO/SCIM)
-- ----------------------------------------------------------------------------
CREATE TABLE member (
    member_id   UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    tenant_id   UUID NOT NULL REFERENCES tenant(tenant_id) ON DELETE CASCADE,
    role        TEXT NOT NULL,
    idp_subject TEXT NOT NULL,
    created_at  TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE (tenant_id, idp_subject)
);
CREATE INDEX idx_member_tenant ON member(tenant_id);

-- ----------------------------------------------------------------------------
--  AGENT IDENTITY — the credential presented at session join
--  policy_hash binds the policy-config the agent operates under (drift guard).
-- ----------------------------------------------------------------------------
CREATE TABLE agent_identity (
    agent_id         UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    tenant_id        UUID NOT NULL REFERENCES tenant(tenant_id) ON DELETE CASCADE,
    cert_fingerprint TEXT NOT NULL UNIQUE,
    model_version    TEXT NOT NULL,
    policy_hash      TEXT NOT NULL,
    status           agent_status NOT NULL DEFAULT 'active',
    created_at       TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX idx_agent_tenant ON agent_identity(tenant_id);

-- ----------------------------------------------------------------------------
--  POLICY BUNDLE — versioned Cedar policy. Contents are NOT stored here in
--  plaintext where isolation matters; this row carries metadata + hash, and a
--  reference to the encrypted/served bundle. bundle_hash is pinned by sessions.
-- ----------------------------------------------------------------------------
CREATE TABLE policy_bundle (
    policy_id       UUID NOT NULL DEFAULT uuid_generate_v4(),
    version         INTEGER NOT NULL,
    tenant_id       UUID NOT NULL REFERENCES tenant(tenant_id) ON DELETE CASCADE,
    cedar_source_ref TEXT NOT NULL,          -- pointer to the stored bundle artifact
    bundle_hash     TEXT NOT NULL,
    published_at    TIMESTAMPTZ NOT NULL DEFAULT now(),
    PRIMARY KEY (policy_id, version)
);
CREATE INDEX idx_policy_tenant ON policy_bundle(tenant_id);

-- ----------------------------------------------------------------------------
--  SESSION CONSTITUTION — the governing object; immutable once active.
--  Frozen content is captured in `body` and `hash` when status -> active.
-- ----------------------------------------------------------------------------
CREATE TABLE constitution (
    constitution_id UUID NOT NULL DEFAULT uuid_generate_v4(),
    version         INTEGER NOT NULL,
    owner_tenant_id UUID NOT NULL REFERENCES tenant(tenant_id),
    body            JSONB NOT NULL,          -- participants, topology, scope, time_bounds, memory_rules, policy_refs, thresholds
    status          constitution_status NOT NULL DEFAULT 'draft',
    hash            TEXT,                    -- set (frozen) when status = 'active'
    created_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
    PRIMARY KEY (constitution_id, version)
);
CREATE UNIQUE INDEX idx_constitution_hash ON constitution(hash) WHERE hash IS NOT NULL;

-- ----------------------------------------------------------------------------
--  SESSION — runtime session instance (state of record; hot runtime state is
--  externalized to the session store).
-- ----------------------------------------------------------------------------
CREATE TABLE session (
    session_id       UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    constitution_id  UUID NOT NULL,
    constitution_ver INTEGER NOT NULL,
    constitution_ref TEXT NOT NULL,          -- the frozen Constitution hash pinned by this session
    state            session_state NOT NULL DEFAULT 'initiating',
    region           region NOT NULL,
    created_at       TIMESTAMPTZ NOT NULL DEFAULT now(),
    closed_at        TIMESTAMPTZ,
    FOREIGN KEY (constitution_id, constitution_ver)
        REFERENCES constitution(constitution_id, version)
);
CREATE INDEX idx_session_state ON session(state);

-- ----------------------------------------------------------------------------
--  SESSION PARTICIPANT — per-party row. proxy participants carry no agent id.
-- ----------------------------------------------------------------------------
CREATE TABLE session_participant (
    session_id      UUID NOT NULL REFERENCES session(session_id) ON DELETE CASCADE,
    tenant_id       UUID NOT NULL REFERENCES tenant(tenant_id),
    mode            participation_mode NOT NULL,
    agent_id        UUID REFERENCES agent_identity(agent_id),   -- NULL in proxy mode
    policy_id       UUID,
    policy_version  INTEGER,
    attestation_ref TEXT,
    joined_at       TIMESTAMPTZ NOT NULL DEFAULT now(),
    PRIMARY KEY (session_id, tenant_id),
    CHECK (mode = 'proxy' OR agent_id IS NOT NULL)    -- bilateral parties must present an agent identity
);
CREATE INDEX idx_participant_tenant ON session_participant(tenant_id);

-- ----------------------------------------------------------------------------
--  AUDIT ENTRY — append-only, hash-chained. One per governed action.
--  entry_hash = sha256(prev_hash + canonical(body)). Mirrored to WORM async.
--  Mutation is forbidden (see trigger + REVOKE below).
-- ----------------------------------------------------------------------------
CREATE TABLE audit_entry (
    entry_hash    TEXT PRIMARY KEY,                  -- content address
    prev_hash     TEXT NOT NULL,
    session_id    UUID NOT NULL REFERENCES session(session_id),
    sequence_no   BIGINT NOT NULL,
    body          JSONB NOT NULL,                    -- sanitized ActionContext + decisions + final + obligations + memory_effect
    final_decision verdict NOT NULL,
    memory_effect memory_effect NOT NULL DEFAULT 'none',
    signatures    JSONB NOT NULL DEFAULT '[]'::jsonb,
    ts            TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE (session_id, sequence_no)                 -- ordering + replay protection (Foundations idempotency)
);
CREATE INDEX idx_audit_session ON audit_entry(session_id);

-- Append-only enforcement: forbid UPDATE/DELETE on the audit log.
CREATE OR REPLACE FUNCTION forbid_audit_mutation() RETURNS trigger AS $$
BEGIN
    RAISE EXCEPTION 'audit_entry is append-only; % is not permitted', TG_OP;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_audit_no_update
    BEFORE UPDATE OR DELETE ON audit_entry
    FOR EACH ROW EXECUTE FUNCTION forbid_audit_mutation();

-- ----------------------------------------------------------------------------
--  GOVERNED MEMORY ENTRY — metadata only (content lives in the memory backend).
--  Enables scope, origin-filtering (I6), and teardown purge (Product Spec §8.5).
-- ----------------------------------------------------------------------------
CREATE TABLE memory_entry (
    memory_id      UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    session_id     UUID REFERENCES session(session_id) ON DELETE CASCADE,
    scope          TEXT NOT NULL CHECK (scope IN ('session', 'persistent')),
    origin_org     UUID NOT NULL REFERENCES tenant(tenant_id),
    origin_session UUID,
    namespace      TEXT NOT NULL,
    content_ref    TEXT NOT NULL,                    -- pointer into the memory backend
    retention      JSONB NOT NULL DEFAULT '{}'::jsonb,  -- {policy, expires_at, permitted_by}
    created_at     TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX idx_memory_session ON memory_entry(session_id);
CREATE INDEX idx_memory_namespace ON memory_entry(namespace);

-- ----------------------------------------------------------------------------
--  BILLING RECORD — metered usage per tenant (and session where applicable).
-- ----------------------------------------------------------------------------
CREATE TABLE billing_record (
    record_id     UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    tenant_id     UUID NOT NULL REFERENCES tenant(tenant_id) ON DELETE CASCADE,
    session_id    UUID REFERENCES session(session_id),
    metered_units JSONB NOT NULL,                    -- {session_hours, action_count, ...}
    period        TEXT NOT NULL,                     -- e.g. '2026-06'
    created_at    TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX idx_billing_tenant_period ON billing_record(tenant_id, period);

-- ============================================================================
--  ROW-LEVEL SECURITY — tenant isolation (Foundations I5).
--  Application sets `SET app.current_tenant = '<tenant_uuid>'` per request;
--  policies restrict every tenant-owned table to the current tenant. This is
--  the floor; stronger deployments use schema/DB-per-tenant.
--  Audit visibility is partitioned: a tenant sees an audit row only if it is a
--  participant in that session.
-- ============================================================================
ALTER TABLE tenant              ENABLE ROW LEVEL SECURITY;
ALTER TABLE member              ENABLE ROW LEVEL SECURITY;
ALTER TABLE agent_identity      ENABLE ROW LEVEL SECURITY;
ALTER TABLE policy_bundle       ENABLE ROW LEVEL SECURITY;
ALTER TABLE session_participant ENABLE ROW LEVEL SECURITY;
ALTER TABLE billing_record      ENABLE ROW LEVEL SECURITY;
ALTER TABLE audit_entry         ENABLE ROW LEVEL SECURITY;

CREATE POLICY tenant_self ON tenant
    USING (tenant_id = current_setting('app.current_tenant')::uuid);
CREATE POLICY member_tenant ON member
    USING (tenant_id = current_setting('app.current_tenant')::uuid);
CREATE POLICY agent_tenant ON agent_identity
    USING (tenant_id = current_setting('app.current_tenant')::uuid);
CREATE POLICY policy_tenant ON policy_bundle
    USING (tenant_id = current_setting('app.current_tenant')::uuid);
CREATE POLICY participant_tenant ON session_participant
    USING (tenant_id = current_setting('app.current_tenant')::uuid);
CREATE POLICY billing_tenant ON billing_record
    USING (tenant_id = current_setting('app.current_tenant')::uuid);

-- Audit: a tenant may read an entry only for sessions it participates in.
CREATE POLICY audit_participant ON audit_entry
    USING (EXISTS (
        SELECT 1 FROM session_participant sp
        WHERE sp.session_id = audit_entry.session_id
          AND sp.tenant_id  = current_setting('app.current_tenant')::uuid
    ));

-- Append-only at the privilege level too: revoke mutation grants from the app role.
-- (Adjust role name to your deployment.)
-- REVOKE UPDATE, DELETE ON audit_entry FROM pact_app;

COMMIT;

-- ============================================================================
--  NOTES FOR IMPLEMENTERS
--  - canonical(body): use the single canonical serialization from Foundations
--    §5 (deterministic field order, normalized encoding) so the Gateway (01)
--    and Audit Writer (08) produce identical hashes.
--  - The session store (Redis or equivalent) holds SessionRuntime: status,
--    affects-routing table, next_sequence_no, warm engine endpoints,
--    last_attestation_ok_at. It is NOT this database (Foundations §9).
--  - Enclave-resident data (policy rules, entity data) is never written here.
--  - WORM mirror: audit_entry rows are replicated to region-pinned WORM object
--    storage asynchronously; this table is the queryable system of record.
-- ============================================================================
