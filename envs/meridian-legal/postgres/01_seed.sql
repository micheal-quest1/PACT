-- =============================================================================
-- Meridian Legal LLP — Seed Data
-- =============================================================================
-- Members, matter, deal room documents, DD checklist, privilege log.
-- UUIDs are deterministic for dev stability (replaced by bootstrap.sh in prod).
-- =============================================================================

-- Members
INSERT INTO meridian_member (member_id, email, full_name, role, department) VALUES
    ('a1000000-0000-0000-0000-000000000001', 'sarah.chen@meridian-legal.ai',
     'Sarah Chen', 'partner', 'M&A'),
    ('a1000000-0000-0000-0000-000000000002', 'james.whitfield@meridian-legal.ai',
     'James Whitfield', 'associate', 'M&A'),
    ('a1000000-0000-0000-0000-000000000003', 'priya.nair@meridian-legal.ai',
     'Priya Nair', 'paralegal', 'M&A'),
    ('a1000000-0000-0000-0000-000000000004', 'admin@meridian-legal.ai',
     'System Admin', 'admin', 'Operations');

-- Primary M&A Matter: NovaTrial Acquisition Due Diligence
INSERT INTO matter (
    matter_id, matter_number, client_name, target_company,
    matter_type, matter_stage, estimated_deal_value_usd, governing_law,
    open_date, expected_close_date, lead_partner_id, billing_rate_usd_hr
) VALUES (
    'b2000000-0000-0000-0000-000000000001',
    'ML-2026-0041',
    'Helion Pharma Inc.',           -- The pharma company acquiring NovaTrial
    'NovaTrial CRO',
    'acquisition',
    'due_diligence',
    500000000,                      -- $500M estimated deal value
    'Delaware',
    '2026-06-01',
    '2026-10-15',
    'a1000000-0000-0000-0000-000000000001',
    850.00                          -- PRIVILEGED: $850/hr billing rate
);

-- Deal Room Documents
INSERT INTO deal_document (
    document_id, matter_id, document_type, title, classification,
    version, counterparty_approved, created_by_id, content_json
) VALUES
    -- NDA between Meridian (on behalf of Helion) and NovaTrial
    ('c3000000-0000-0000-0000-000000000001',
     'b2000000-0000-0000-0000-000000000001',
     'nda', 'Mutual Non-Disclosure Agreement — Helion Pharma / NovaTrial CRO',
     'confidential', 1, TRUE,
     'a1000000-0000-0000-0000-000000000001',
     '{
       "parties": ["Helion Pharma Inc.", "NovaTrial CRO"],
       "effective_date": "2026-06-10",
       "governing_law": "Delaware",
       "term_years": 3,
       "purpose": "Evaluation of potential acquisition of NovaTrial CRO by Helion Pharma Inc.",
       "permitted_disclosures": [
         "Clinical trial portfolio summaries (aggregate only)",
         "Regulatory filing status (no raw submissions)",
         "IP portfolio existence (not methodology)"
       ],
       "excluded_disclosures": [
         "Raw patient data",
         "Proprietary trial methodologies",
         "Unreported adverse events"
       ],
       "cfr_reference": "Not applicable (commercial NDA)"
     }'::jsonb),

    -- Term Sheet
    ('c3000000-0000-0000-0000-000000000002',
     'b2000000-0000-0000-0000-000000000001',
     'term_sheet', 'Indicative Term Sheet — Acquisition of NovaTrial CRO',
     'privileged', 1, FALSE,        -- PRIVILEGED: counterparty cannot see
     'a1000000-0000-0000-0000-000000000001',
     '{
       "deal_structure": "100% stock acquisition",
       "indicative_valuation": "480M-520M USD",
       "due_diligence_period_days": 60,
       "key_conditions": [
         "Clean Phase 2 completion on NCT02076503",
         "No material adverse regulatory findings",
         "IP portfolio free of encumbrances"
       ],
       "note": "PRIVILEGED — attorney work product"
     }'::jsonb),

    -- DD Checklist (shared reference — what Harvey will review)
    ('c3000000-0000-0000-0000-000000000003',
     'b2000000-0000-0000-0000-000000000001',
     'dd_checklist', 'Due Diligence Checklist — NovaTrial Clinical Portfolio',
     'confidential', 1, TRUE,       -- counterparty can see the checklist (not the answers)
     'a1000000-0000-0000-0000-000000000001',
     '{
       "checklist_version": "1.0",
       "categories": ["clinical_trials", "regulatory", "ip_portfolio"],
       "total_items": 12,
       "note": "Shared with NovaTrial for preparation"
     }'::jsonb),

    -- Internal Risk Assessment (privileged work product)
    ('c3000000-0000-0000-0000-000000000004',
     'b2000000-0000-0000-0000-000000000001',
     'risk_assessment', 'Preliminary Regulatory Risk Memo — NovaTrial CRO',
     'work_product', 1, FALSE,      -- WORK PRODUCT: counterparty cannot see
     'a1000000-0000-0000-0000-000000000002',
     '{
       "classification": "Attorney Work Product — Privileged",
       "prepared_by": "James Whitfield, Associate",
       "key_risks": [
         "Phase 2 adverse event reporting completeness",
         "FDA 21 CFR Part 11 electronic records compliance",
         "IP assignment gaps in trial protocols"
       ],
       "note": "WORK PRODUCT — Harvey policy blocks cross-org sharing"
     }'::jsonb);

-- DD Checklist Items (what Harvey needs to review in NovaTrial's data)
INSERT INTO dd_checklist_item (
    item_id, matter_id, category, item_description,
    target_resource, status, risk_level
) VALUES
    ('d4000000-0000-0000-0000-000000000001',
     'b2000000-0000-0000-0000-000000000001',
     'clinical_trials',
     'Review Phase 2 completion status for prostate cancer trial (NCT02076503)',
     'novatrial:approved-for-dd/NCT02076503',
     'pending', 'high'),

    ('d4000000-0000-0000-0000-000000000002',
     'b2000000-0000-0000-0000-000000000001',
     'clinical_trials',
     'Confirm enrollment completion and adverse event summary for genotoxicity study (NCT00167427)',
     'novatrial:approved-for-dd/NCT00167427',
     'pending', 'medium'),

    ('d4000000-0000-0000-0000-000000000003',
     'b2000000-0000-0000-0000-000000000001',
     'clinical_trials',
     'Review Phase 2 outcomes for Ewing sarcoma trial (NCT01492673) — premature termination flag',
     'novatrial:approved-for-dd/NCT01492673',
     'pending', 'critical'),

    ('d4000000-0000-0000-0000-000000000004',
     'b2000000-0000-0000-0000-000000000001',
     'regulatory',
     'Confirm IND application status and FDA correspondence history',
     'novatrial:approved-for-dd/regulatory-status',
     'pending', 'high'),

    ('d4000000-0000-0000-0000-000000000005',
     'b2000000-0000-0000-0000-000000000001',
     'ip_portfolio',
     'Confirm existence and validity of patent portfolio covering trial methodologies',
     'novatrial:approved-for-dd/ip-summary',
     'pending', 'high'),

    ('d4000000-0000-0000-0000-000000000006',
     'b2000000-0000-0000-0000-000000000001',
     'clinical_trials',
     'Aggregate adverse event summary across all completed trials',
     'novatrial:approved-for-dd/aggregate-ae-summary',
     'pending', 'critical');

-- Privilege Log (STRICTLY INTERNAL — Harvey policy hard-blocks cross-org access)
INSERT INTO privilege_log (
    log_id, matter_id, document_id, privilege_type,
    description, author, date_of_communication, logged_by_id
) VALUES
    ('e5000000-0000-0000-0000-000000000001',
     'b2000000-0000-0000-0000-000000000001',
     'c3000000-0000-0000-0000-000000000002',
     'work_product',
     'Indicative term sheet with valuation range and deal conditions — prepared by counsel',
     'Sarah Chen, Partner; James Whitfield, Associate',
     '2026-06-15',
     'a1000000-0000-0000-0000-000000000001'),

    ('e5000000-0000-0000-0000-000000000002',
     'b2000000-0000-0000-0000-000000000001',
     'c3000000-0000-0000-0000-000000000004',
     'work_product',
     'Internal regulatory risk memo identifying Phase 2 adverse event reporting gaps',
     'James Whitfield, Associate',
     '2026-06-20',
     'a1000000-0000-0000-0000-000000000001');
