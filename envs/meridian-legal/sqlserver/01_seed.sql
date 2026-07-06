-- =============================================================================
-- Meridian Legal LLP — Seed Data (T-SQL / SQL Server 2022)
-- =============================================================================
USE meridian_db;
GO

-- Members
INSERT INTO meridian_member (member_id, email, full_name, role, department) VALUES
    ('A1000000-0000-0000-0000-000000000001', 'sarah.chen@meridian-legal.ai',
     'Sarah Chen', 'partner', 'M&A'),
    ('A1000000-0000-0000-0000-000000000002', 'james.whitfield@meridian-legal.ai',
     'James Whitfield', 'associate', 'M&A'),
    ('A1000000-0000-0000-0000-000000000003', 'priya.nair@meridian-legal.ai',
     'Priya Nair', 'paralegal', 'M&A'),
    ('A1000000-0000-0000-0000-000000000004', 'admin@meridian-legal.ai',
     'System Admin', 'admin', 'Operations');
GO

-- Primary M&A Matter: NovaTrial Acquisition Due Diligence
INSERT INTO matter (
    matter_id, matter_number, client_name, target_company,
    matter_type, matter_stage, estimated_deal_value_usd, governing_law,
    open_date, expected_close_date, lead_partner_id, billing_rate_usd_hr
) VALUES (
    'B2000000-0000-0000-0000-000000000001',
    'ML-2026-0041',
    'Helion Pharma Inc.',
    'NovaTrial CRO',
    'acquisition',
    'due_diligence',
    500000000,
    'Delaware',
    '2026-06-01',
    '2026-10-15',
    'A1000000-0000-0000-0000-000000000001',
    850.00   -- PRIVILEGED: $850/hr billing rate — Cedar policy blocks cross-org exposure
);
GO

-- Deal Room Documents
INSERT INTO deal_document (
    document_id, matter_id, document_type, title, classification,
    version, counterparty_approved, created_by_id, content_json
) VALUES
    -- NDA (counterparty_approved = 1 → can be referenced in cross-org sessions)
    ('C3000000-0000-0000-0000-000000000001',
     'B2000000-0000-0000-0000-000000000001',
     'nda',
     'Mutual Non-Disclosure Agreement — Helion Pharma / NovaTrial CRO',
     'confidential', 1, 1,
     'A1000000-0000-0000-0000-000000000001',
     N'{"parties":["Helion Pharma Inc.","NovaTrial CRO"],"effective_date":"2026-06-10","governing_law":"Delaware","term_years":3,"purpose":"Evaluation of potential acquisition of NovaTrial CRO by Helion Pharma Inc.","permitted_disclosures":["Clinical trial portfolio summaries (aggregate only)","Regulatory filing status (no raw submissions)","IP portfolio existence (not methodology)"],"excluded_disclosures":["Raw patient data","Proprietary trial methodologies","Unreported adverse events"]}'),

    -- Term Sheet (counterparty_approved = 0 → PRIVILEGED, blocked by Cedar)
    ('C3000000-0000-0000-0000-000000000002',
     'B2000000-0000-0000-0000-000000000001',
     'term_sheet',
     'Indicative Term Sheet — Acquisition of NovaTrial CRO',
     'privileged', 1, 0,
     'A1000000-0000-0000-0000-000000000001',
     N'{"deal_structure":"100% stock acquisition","indicative_valuation":"480M-520M USD","due_diligence_period_days":60,"key_conditions":["Clean Phase 2 completion on NCT02076503","No material adverse regulatory findings","IP portfolio free of encumbrances"],"note":"PRIVILEGED — attorney work product"}'),

    -- DD Checklist (counterparty_approved = 1 → NovaTrial can see the checklist)
    ('C3000000-0000-0000-0000-000000000003',
     'B2000000-0000-0000-0000-000000000001',
     'dd_checklist',
     'Due Diligence Checklist — NovaTrial Clinical Portfolio',
     'confidential', 1, 1,
     'A1000000-0000-0000-0000-000000000001',
     N'{"checklist_version":"1.0","categories":["clinical_trials","regulatory","ip_portfolio"],"total_items":12,"note":"Shared with NovaTrial for preparation"}'),

    -- Internal Risk Memo (counterparty_approved = 0 → work product, hard-blocked)
    ('C3000000-0000-0000-0000-000000000004',
     'B2000000-0000-0000-0000-000000000001',
     'risk_assessment',
     'Preliminary Regulatory Risk Memo — NovaTrial CRO',
     'work_product', 1, 0,
     'A1000000-0000-0000-0000-000000000002',
     N'{"classification":"Attorney Work Product — Privileged","prepared_by":"James Whitfield, Associate","key_risks":["Phase 2 adverse event reporting completeness","FDA 21 CFR Part 11 electronic records compliance","IP assignment gaps in trial protocols"],"note":"WORK PRODUCT — Harvey policy blocks cross-org sharing"}');
GO

-- DD Checklist Items (what Harvey will query in NovaTrial's approved-for-dd data)
INSERT INTO dd_checklist_item (
    item_id, matter_id, category, item_description,
    target_resource, status, risk_level
) VALUES
    ('D4000000-0000-0000-0000-000000000001',
     'B2000000-0000-0000-0000-000000000001',
     'clinical_trials',
     'Review Phase 2 completion status for prostate cancer trial (NCT02076503)',
     'novatrial:approved-for-dd/NCT02076503',
     'pending', 'high'),

    ('D4000000-0000-0000-0000-000000000002',
     'B2000000-0000-0000-0000-000000000001',
     'clinical_trials',
     'Confirm enrollment completion and adverse event summary for genotoxicity study (NCT00167427)',
     'novatrial:approved-for-dd/NCT00167427',
     'pending', 'medium'),

    ('D4000000-0000-0000-0000-000000000003',
     'B2000000-0000-0000-0000-000000000001',
     'clinical_trials',
     'Review Phase 2 outcomes for Ewing sarcoma trial (NCT01492673) — premature termination flag',
     'novatrial:approved-for-dd/NCT01492673',
     'pending', 'critical'),

    ('D4000000-0000-0000-0000-000000000004',
     'B2000000-0000-0000-0000-000000000001',
     'regulatory',
     'Confirm IND application status and FDA correspondence history',
     'novatrial:approved-for-dd/regulatory-status',
     'pending', 'high'),

    ('D4000000-0000-0000-0000-000000000005',
     'B2000000-0000-0000-0000-000000000001',
     'ip_portfolio',
     'Confirm existence and validity of patent portfolio covering trial methodologies',
     'novatrial:approved-for-dd/ip-summary',
     'pending', 'high'),

    ('D4000000-0000-0000-0000-000000000006',
     'B2000000-0000-0000-0000-000000000001',
     'clinical_trials',
     'Aggregate adverse event summary across all completed trials',
     'novatrial:approved-for-dd/aggregate-ae-summary',
     'pending', 'critical');
GO

-- Privilege Log (STRICTLY INTERNAL — Cedar policy hard-blocks all cross-org access)
INSERT INTO privilege_log (
    log_id, matter_id, document_id, privilege_type,
    description, author, date_of_communication, logged_by_id
) VALUES
    ('E5000000-0000-0000-0000-000000000001',
     'B2000000-0000-0000-0000-000000000001',
     'C3000000-0000-0000-0000-000000000002',
     'work_product',
     'Indicative term sheet with valuation range and deal conditions — prepared by counsel',
     'Sarah Chen, Partner; James Whitfield, Associate',
     '2026-06-15',
     'A1000000-0000-0000-0000-000000000001'),

    ('E5000000-0000-0000-0000-000000000002',
     'B2000000-0000-0000-0000-000000000001',
     'C3000000-0000-0000-0000-000000000004',
     'work_product',
     'Internal regulatory risk memo identifying Phase 2 adverse event reporting gaps',
     'James Whitfield, Associate',
     '2026-06-20',
     'A1000000-0000-0000-0000-000000000001');
GO

PRINT 'Meridian Legal LLP seed data loaded successfully.';
GO
