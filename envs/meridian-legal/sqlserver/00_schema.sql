-- =============================================================================
-- Meridian Legal LLP — Internal Database Schema (T-SQL / SQL Server 2022)
-- =============================================================================
-- This is Meridian Legal's private Microsoft SQL Server database.
-- PACT has NO direct access to this schema.
-- PACT governs what Harvey (the agent) does — not what is stored here.
--
-- Key T-SQL differences from PostgreSQL:
--   UNIQUEIDENTIFIER instead of UUID
--   NVARCHAR(MAX) instead of TEXT/JSONB
--   BIT instead of BOOLEAN
--   DATETIMEOFFSET instead of TIMESTAMPTZ
--   NEWID() instead of uuid_generate_v4()
--   GETUTCDATE() instead of NOW()
--   CHECK constraints instead of ENUMs
--   No arrays — comma-separated or JSON stored in NVARCHAR(MAX)
-- =============================================================================

USE master;
GO

-- Create the database
IF NOT EXISTS (SELECT name FROM sys.databases WHERE name = 'meridian_db')
BEGIN
    CREATE DATABASE meridian_db
    COLLATE SQL_Latin1_General_CP1_CI_AS;
END
GO

USE meridian_db;
GO

-- =============================================================================
-- MEMBERS — Meridian Legal staff
-- =============================================================================
CREATE TABLE meridian_member (
    member_id       UNIQUEIDENTIFIER    NOT NULL DEFAULT NEWID()     CONSTRAINT PK_member PRIMARY KEY,
    email           NVARCHAR(255)       NOT NULL                     CONSTRAINT UQ_member_email UNIQUE,
    full_name       NVARCHAR(255)       NOT NULL,
    role            NVARCHAR(50)        NOT NULL
                    CONSTRAINT CHK_member_role CHECK (role IN (
                        'partner', 'associate', 'paralegal', 'admin')),
    department      NVARCHAR(100)       NOT NULL DEFAULT 'M&A',
    created_at      DATETIMEOFFSET      NOT NULL DEFAULT SYSDATETIMEOFFSET(),
    is_active       BIT                 NOT NULL DEFAULT 1
);
GO

-- =============================================================================
-- MATTERS — Active client legal engagements (attorney-client privileged)
-- =============================================================================
CREATE TABLE matter (
    matter_id               UNIQUEIDENTIFIER    NOT NULL DEFAULT NEWID()  CONSTRAINT PK_matter PRIMARY KEY,
    matter_number           NVARCHAR(50)        NOT NULL                  CONSTRAINT UQ_matter_number UNIQUE,
    client_name             NVARCHAR(255)       NOT NULL,
    target_company          NVARCHAR(255)       NULL,
    matter_type             NVARCHAR(50)        NOT NULL
                            CONSTRAINT CHK_matter_type CHECK (matter_type IN (
                                'acquisition', 'merger', 'due_diligence',
                                'contract_review', 'litigation', 'regulatory')),
    matter_stage            NVARCHAR(50)        NOT NULL
                            CONSTRAINT CHK_matter_stage CHECK (matter_stage IN (
                                'intake', 'due_diligence', 'negotiation',
                                'closing', 'post_closing', 'closed')),
    estimated_deal_value_usd BIGINT             NULL,
    governing_law           NVARCHAR(100)       NOT NULL DEFAULT 'Delaware',
    open_date               DATE                NOT NULL,
    expected_close_date     DATE                NULL,
    lead_partner_id         UNIQUEIDENTIFIER    NULL
                            CONSTRAINT FK_matter_partner FOREIGN KEY REFERENCES meridian_member(member_id),
    billing_rate_usd_hr     DECIMAL(10,2)       NULL,   -- PRIVILEGED: never exposed cross-org
    created_at              DATETIMEOFFSET      NOT NULL DEFAULT SYSDATETIMEOFFSET(),
    updated_at              DATETIMEOFFSET      NOT NULL DEFAULT SYSDATETIMEOFFSET()
);
GO

EXEC sys.sp_addextendedproperty
    @name = N'MS_Description',
    @value = N'PRIVILEGED — billing_rate_usd_hr must never be exposed via PACT sessions',
    @level0type = N'SCHEMA', @level0name = N'dbo',
    @level1type = N'TABLE',  @level1name = N'matter',
    @level2type = N'COLUMN', @level2name = N'billing_rate_usd_hr';
GO

-- =============================================================================
-- DEAL DOCUMENTS — Deal room documents linked to a matter
-- =============================================================================
CREATE TABLE deal_document (
    document_id             UNIQUEIDENTIFIER    NOT NULL DEFAULT NEWID()  CONSTRAINT PK_doc PRIMARY KEY,
    matter_id               UNIQUEIDENTIFIER    NOT NULL
                            CONSTRAINT FK_doc_matter FOREIGN KEY REFERENCES matter(matter_id),
    document_type           NVARCHAR(50)        NOT NULL
                            CONSTRAINT CHK_doc_type CHECK (document_type IN (
                                'nda', 'term_sheet', 'acquisition_agreement',
                                'dd_checklist', 'dd_report', 'privilege_log',
                                'engagement_letter', 'regulatory_memo',
                                'risk_assessment', 'board_resolution')),
    title                   NVARCHAR(500)       NOT NULL,
    classification          NVARCHAR(50)        NOT NULL
                            CONSTRAINT CHK_doc_class CHECK (classification IN (
                                'privileged', 'work_product', 'confidential', 'public')),
    version                 INT                 NOT NULL DEFAULT 1,
    content_json            NVARCHAR(MAX)       NULL,   -- JSON stored as NVARCHAR(MAX)
    file_path               NVARCHAR(500)       NULL,
    counterparty_approved   BIT                 NOT NULL DEFAULT 0,
    created_by_id           UNIQUEIDENTIFIER    NULL
                            CONSTRAINT FK_doc_creator FOREIGN KEY REFERENCES meridian_member(member_id),
    created_at              DATETIMEOFFSET      NOT NULL DEFAULT SYSDATETIMEOFFSET(),
    updated_at              DATETIMEOFFSET      NOT NULL DEFAULT SYSDATETIMEOFFSET(),
    CONSTRAINT CHK_content_json_valid CHECK (
        content_json IS NULL OR ISJSON(content_json) = 1
    )
);
GO

-- =============================================================================
-- DD CHECKLIST ITEMS — What Harvey will query in NovaTrial's data
-- =============================================================================
CREATE TABLE dd_checklist_item (
    item_id             UNIQUEIDENTIFIER    NOT NULL DEFAULT NEWID()  CONSTRAINT PK_dd_item PRIMARY KEY,
    matter_id           UNIQUEIDENTIFIER    NOT NULL
                        CONSTRAINT FK_dd_matter FOREIGN KEY REFERENCES matter(matter_id),
    category            NVARCHAR(50)        NOT NULL
                        CONSTRAINT CHK_dd_category CHECK (category IN (
                            'clinical_trials', 'regulatory', 'ip_portfolio',
                            'financial', 'contracts', 'litigation', 'compliance')),
    item_description    NVARCHAR(MAX)       NOT NULL,
    target_resource     NVARCHAR(500)       NULL,   -- NovaTrial resource Harvey will query
    status              NVARCHAR(50)        NOT NULL DEFAULT 'pending'
                        CONSTRAINT CHK_dd_status CHECK (status IN (
                            'pending', 'in_progress', 'completed', 'blocked')),
    risk_level          NVARCHAR(20)        NULL
                        CONSTRAINT CHK_dd_risk CHECK (risk_level IN (
                            'low', 'medium', 'high', 'critical')),
    notes               NVARCHAR(MAX)       NULL,   -- Harvey's internal notes (privileged)
    created_at          DATETIMEOFFSET      NOT NULL DEFAULT SYSDATETIMEOFFSET(),
    completed_at        DATETIMEOFFSET      NULL
);
GO

-- =============================================================================
-- PRIVILEGE LOG — Tracking privileged communications (NEVER leaves Meridian)
-- =============================================================================
CREATE TABLE privilege_log (
    log_id                      UNIQUEIDENTIFIER    NOT NULL DEFAULT NEWID()  CONSTRAINT PK_priv PRIMARY KEY,
    matter_id                   UNIQUEIDENTIFIER    NOT NULL
                                CONSTRAINT FK_priv_matter FOREIGN KEY REFERENCES matter(matter_id),
    document_id                 UNIQUEIDENTIFIER    NULL
                                CONSTRAINT FK_priv_doc FOREIGN KEY REFERENCES deal_document(document_id),
    privilege_type              NVARCHAR(50)        NOT NULL
                                CONSTRAINT CHK_priv_type CHECK (privilege_type IN (
                                    'attorney_client', 'work_product', 'common_interest')),
    description                 NVARCHAR(MAX)       NOT NULL,
    author                      NVARCHAR(500)       NOT NULL,
    date_of_communication       DATE                NOT NULL,
    logged_by_id                UNIQUEIDENTIFIER    NULL
                                CONSTRAINT FK_priv_logged FOREIGN KEY REFERENCES meridian_member(member_id),
    created_at                  DATETIMEOFFSET      NOT NULL DEFAULT SYSDATETIMEOFFSET()
);
GO

EXEC sys.sp_addextendedproperty
    @name = N'MS_Description',
    @value = N'STRICTLY PRIVILEGED — Cedar policy hard-blocks all cross-org session access to this table',
    @level0type = N'SCHEMA', @level0name = N'dbo',
    @level1type = N'TABLE',  @level1name = N'privilege_log';
GO

-- =============================================================================
-- INTERNAL AUDIT — Meridian's own access log (separate from PACT audit)
-- =============================================================================
CREATE TABLE meridian_internal_audit (
    audit_id            UNIQUEIDENTIFIER    NOT NULL DEFAULT NEWID()  CONSTRAINT PK_audit PRIMARY KEY,
    member_id           UNIQUEIDENTIFIER    NULL
                        CONSTRAINT FK_audit_member FOREIGN KEY REFERENCES meridian_member(member_id),
    action              NVARCHAR(100)       NOT NULL,
    resource_type       NVARCHAR(100)       NOT NULL,
    resource_id         UNIQUEIDENTIFIER    NULL,
    pact_session_id     UNIQUEIDENTIFIER    NULL,   -- cross-reference to PACT session
    timestamp           DATETIMEOFFSET      NOT NULL DEFAULT SYSDATETIMEOFFSET()
);
GO

-- =============================================================================
-- INDEXES
-- =============================================================================
CREATE INDEX IX_deal_document_matter     ON deal_document(matter_id);
CREATE INDEX IX_deal_document_class      ON deal_document(classification);
CREATE INDEX IX_dd_checklist_matter      ON dd_checklist_item(matter_id);
CREATE INDEX IX_dd_checklist_status      ON dd_checklist_item(status);
CREATE INDEX IX_privilege_log_matter     ON privilege_log(matter_id);
CREATE INDEX IX_audit_timestamp          ON meridian_internal_audit(timestamp DESC);
GO

-- =============================================================================
-- UPDATE TRIGGER — keep updated_at current (SQL Server equivalent)
-- =============================================================================
CREATE TRIGGER trg_matter_updated_at
ON matter
AFTER UPDATE
AS
BEGIN
    SET NOCOUNT ON;
    UPDATE matter
    SET updated_at = SYSDATETIMEOFFSET()
    FROM matter m
    INNER JOIN inserted i ON m.matter_id = i.matter_id;
END;
GO

CREATE TRIGGER trg_deal_document_updated_at
ON deal_document
AFTER UPDATE
AS
BEGIN
    SET NOCOUNT ON;
    UPDATE deal_document
    SET updated_at = SYSDATETIMEOFFSET()
    FROM deal_document d
    INNER JOIN inserted i ON d.document_id = i.document_id;
END;
GO

PRINT 'Meridian Legal LLP schema created successfully (SQL Server 2022).';
GO
