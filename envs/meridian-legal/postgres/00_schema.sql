-- =============================================================================
-- Meridian Legal LLP — Internal Database Schema
-- =============================================================================
-- This is Meridian Legal's own private database.
-- PACT has NO direct access to this schema.
-- PACT governs what Harvey (the agent) does, not what's stored here.
-- =============================================================================

-- Extensions
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";
CREATE EXTENSION IF NOT EXISTS "pg_trgm";  -- for full-text search on documents

-- =============================================================================
-- MEMBERS — Meridian Legal staff
-- =============================================================================
CREATE TABLE meridian_member (
    member_id       UUID        PRIMARY KEY DEFAULT uuid_generate_v4(),
    email           TEXT        NOT NULL UNIQUE,
    full_name       TEXT        NOT NULL,
    role            TEXT        NOT NULL CHECK (role IN ('partner', 'associate', 'paralegal', 'admin')),
    department      TEXT        NOT NULL DEFAULT 'M&A',
    created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    is_active       BOOLEAN     NOT NULL DEFAULT TRUE
);

-- =============================================================================
-- MATTERS — Active client engagements
-- A "matter" is a legal case/engagement. This is privileged information.
-- =============================================================================
CREATE TABLE matter (
    matter_id           UUID        PRIMARY KEY DEFAULT uuid_generate_v4(),
    matter_number       TEXT        NOT NULL UNIQUE,  -- e.g. ML-2026-0041
    client_name         TEXT        NOT NULL,
    target_company      TEXT,                          -- for M&A matters
    matter_type         TEXT        NOT NULL CHECK (matter_type IN (
                            'acquisition', 'merger', 'due_diligence',
                            'contract_review', 'litigation', 'regulatory')),
    matter_stage        TEXT        NOT NULL CHECK (matter_stage IN (
                            'intake', 'due_diligence', 'negotiation',
                            'closing', 'post_closing', 'closed')),
    estimated_deal_value_usd BIGINT,
    governing_law       TEXT        NOT NULL DEFAULT 'Delaware',
    open_date           DATE        NOT NULL,
    expected_close_date DATE,
    lead_partner_id     UUID        REFERENCES meridian_member(member_id),
    billing_rate_usd_hr NUMERIC(10,2),  -- PRIVILEGED: never leaves Meridian
    created_at          TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at          TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
COMMENT ON TABLE matter IS 'Active legal engagements. Billing rates are attorney-client privileged.';
COMMENT ON COLUMN matter.billing_rate_usd_hr IS 'PRIVILEGED — never expose to counterparty or PACT';

-- =============================================================================
-- DOCUMENTS — Deal room documents linked to a matter
-- =============================================================================
CREATE TYPE document_classification AS ENUM (
    'privileged',       -- attorney-client privilege: Harvey cannot share
    'work_product',     -- attorney work product: Harvey cannot share
    'confidential',     -- confidential but not privileged: governed sharing allowed
    'public'            -- fully public
);

CREATE TABLE deal_document (
    document_id         UUID                    PRIMARY KEY DEFAULT uuid_generate_v4(),
    matter_id           UUID                    NOT NULL REFERENCES matter(matter_id),
    document_type       TEXT                    NOT NULL CHECK (document_type IN (
                            'nda', 'term_sheet', 'acquisition_agreement',
                            'dd_checklist', 'dd_report', 'privilege_log',
                            'engagement_letter', 'regulatory_memo',
                            'risk_assessment', 'board_resolution')),
    title               TEXT                    NOT NULL,
    classification      document_classification NOT NULL,
    version             INTEGER                 NOT NULL DEFAULT 1,
    content_json        JSONB,                  -- structured document content
    file_path           TEXT,                   -- path to raw file if applicable
    counterparty_approved BOOLEAN               NOT NULL DEFAULT FALSE,
                                                -- TRUE = can be shared via PACT session
    created_by_id       UUID                    REFERENCES meridian_member(member_id),
    created_at          TIMESTAMPTZ             NOT NULL DEFAULT NOW(),
    updated_at          TIMESTAMPTZ             NOT NULL DEFAULT NOW()
);
COMMENT ON COLUMN deal_document.counterparty_approved IS
    'If FALSE, Harvey policy denies sharing this document in any cross-org session';

-- =============================================================================
-- DUE DILIGENCE CHECKLIST — Items Harvey will review in NovaTrial's data
-- =============================================================================
CREATE TABLE dd_checklist_item (
    item_id             UUID        PRIMARY KEY DEFAULT uuid_generate_v4(),
    matter_id           UUID        NOT NULL REFERENCES matter(matter_id),
    category            TEXT        NOT NULL CHECK (category IN (
                            'clinical_trials', 'regulatory', 'ip_portfolio',
                            'financial', 'contracts', 'litigation', 'compliance')),
    item_description    TEXT        NOT NULL,
    target_resource     TEXT,       -- the NovaTrial resource Harvey needs to query
    status              TEXT        NOT NULL DEFAULT 'pending' CHECK (status IN (
                            'pending', 'in_progress', 'completed', 'blocked')),
    risk_level          TEXT        CHECK (risk_level IN ('low', 'medium', 'high', 'critical')),
    notes               TEXT,       -- Harvey's internal notes (privileged)
    created_at          TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    completed_at        TIMESTAMPTZ
);

-- =============================================================================
-- PRIVILEGE LOG — Tracking privileged communications (never leaves Meridian)
-- =============================================================================
CREATE TABLE privilege_log (
    log_id              UUID        PRIMARY KEY DEFAULT uuid_generate_v4(),
    matter_id           UUID        NOT NULL REFERENCES matter(matter_id),
    document_id         UUID        REFERENCES deal_document(document_id),
    privilege_type      TEXT        NOT NULL CHECK (privilege_type IN (
                            'attorney_client', 'work_product', 'common_interest')),
    description         TEXT        NOT NULL,
    author              TEXT        NOT NULL,
    date_of_communication DATE      NOT NULL,
    logged_by_id        UUID        REFERENCES meridian_member(member_id),
    created_at          TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
COMMENT ON TABLE privilege_log IS
    'STRICTLY PRIVILEGED — Harvey policy explicitly denies any cross-org session access to this table.';

-- =============================================================================
-- AUDIT — Meridian's internal access log (separate from PACT audit)
-- =============================================================================
CREATE TABLE meridian_internal_audit (
    audit_id            UUID        PRIMARY KEY DEFAULT uuid_generate_v4(),
    member_id           UUID        REFERENCES meridian_member(member_id),
    action              TEXT        NOT NULL,
    resource_type       TEXT        NOT NULL,
    resource_id         UUID,
    pact_session_id     UUID,       -- cross-reference to PACT session if action was cross-org
    timestamp           TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- Indexes for query performance
CREATE INDEX idx_deal_document_matter   ON deal_document(matter_id);
CREATE INDEX idx_deal_document_class    ON deal_document(classification);
CREATE INDEX idx_dd_checklist_matter    ON dd_checklist_item(matter_id);
CREATE INDEX idx_dd_checklist_status    ON dd_checklist_item(status);
CREATE INDEX idx_privilege_log_matter   ON privilege_log(matter_id);

-- Update trigger
CREATE OR REPLACE FUNCTION update_updated_at()
RETURNS TRIGGER AS $$
BEGIN NEW.updated_at = NOW(); RETURN NEW; END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_matter_updated_at
    BEFORE UPDATE ON matter
    FOR EACH ROW EXECUTE FUNCTION update_updated_at();

CREATE TRIGGER trg_deal_document_updated_at
    BEFORE UPDATE ON deal_document
    FOR EACH ROW EXECUTE FUNCTION update_updated_at();
