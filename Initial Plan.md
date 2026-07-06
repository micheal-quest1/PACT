# PACT — Two-Organisation Foundation (Final Plan)

> Based on: PACT_Complete_Use_Case_Framework.docx, PACT_MVP_Build_Specification.docx,
> PACT_Product_Build_Specification.docx

---

## What the Documents Tell Us

### The Correct Vertical: Legal (Tier 1A — Primary Beachhead)

The Use Case Framework is unambiguous:

> *"Law firms are active AI buyers with single decision-makers, documented cross-org pain,
> and existing Harvey/Legora deployments that expose the inter-org governance gap directly."*
> — PACT_Complete_Use_Case_Framework, Tier Table

And the primary use case verbatim:

> *"Law Firm ↔ Corporate Client: M&A Due Diligence*
> *Harvey (law firm) ↔ Harvey or Legora (corporate client)*
> *The law firm's Harvey agent must access privileged matter files.
> The corporate client's agent needs joint analysis outputs but cannot see
> the firm's full work product or billing strategy."*

And from MVP spec Section 2.1:

> *"a pharma company's agent and a CRO's agent on trial data"* — named explicitly as
> the second archetypal use case.

Life Sciences / Pharma is Tier 3 (Year 2 — 12–18 months sales cycle).
**We should NOT use it as the primary use case for the development sandbox.**

### The Correct Use Case

**A law firm (Harvey) doing M&A due diligence on a CRO** sits perfectly at the
intersection of Tier 1A (Legal) and the pharma/CRO scenario the MVP spec names:

```
Meridian Legal LLP (AmLaw 200 M&A firm)
    └── Harvey agent — conducting due diligence on behalf of pharma client
    └── Own data: deal room — NDAs, term sheets, matter files, work product,
                              acquisition agreements, privilege log
    └── Policy: protect work product and billing strategy; allow analysis of
                target company data; never expose privilege log to counterparty

NovaTrial CRO (Contract Research Organisation)
    └── Atlas agent — their research data AI (or none — asymmetric mode option)
    └── Own data: clinical trial portfolio — real NCT records from ClinicalTrials.gov,
                   protocol documents, regulatory submissions, IP licensing terms
    └── Policy: allow due diligence queries on approved trial data; deny raw
                patient data export; deny access to proprietary methodology docs
```

**The Business Tension (Why PACT Exists Here):**
Meridian Legal's Harvey needs to review NovaTrial's clinical pipeline to advise
on a $500M acquisition. NovaTrial cannot expose raw patient data, proprietary
trial methodologies, or unreported adverse events. No safe mechanism exists today.
PACT governs every action Harvey makes against NovaTrial's data — both sides
enforce simultaneously. This is a real, live, undefended problem.

---

## Architecture: Three Completely Isolated Environments

```
┌────────────────────────┐         ┌────────────────────────┐
│  envs/meridian-legal/   │         │  envs/novatrial/        │
│  ─────────────────────  │         │  ──────────────────     │
│  Postgres: deal room DB │         │  Postgres: trials DB    │
│  Redis: agent cache     │         │  Redis: agent cache     │
│  Harvey (MCP agent)     │         │  Atlas (MCP agent)      │
│  Harvey's Cedar policy  │         │  NovaTrial Cedar policy │
│  Data: M&A deal docs    │         │  Data: real NCT trials  │
│  Network: meridian-net  │         │  Network: novatrial-net │
│  Ports: 5433, 6380, 4001│         │  Ports: 5434, 6381, 4002│
└──────────┬─────────────┘         └──────────┬─────────────┘
           │ mTLS (Harvey cert)               │ mTLS (Atlas cert)
           └────────────┐   ┌─────────────────┘
                        ↓   ↓
           ┌─────────────────────────────────────┐
           │  envs/pact-platform/                 │
           │  ──────────────────────────────────  │
           │  Postgres: PACT control plane DB      │  ← pact_schema.sql
           │  Redis: session runtime state         │
           │  pgBouncer: connection pooling        │
           │  OTel Collector: distributed tracing  │
           │  Prometheus + Grafana: SLO dashboards │
           │  Network: pact-net                    │
           │  Ports: 5432, 6432, 6379, 50051, 3000│
           └─────────────────────────────────────┘
```

**Rule:** No shared databases. No shared Redis. No shared networks.
Each org environment is opaque to the other. They interact ONLY through the PACT
enforcement gateway on mTLS-authenticated connections.

---

## Real Data Strategy

### Meridian Legal — M&A Deal Room Data

Source: Constructed from real public M&A legal document structures.
Real SEC EDGAR filings and FDA regulatory submission structures will be used as templates.

```
data/deal-room/
├── matter/
│   ├── matter-001-novatrial-acquisition.json
│   │   { matter_id, client, target, deal_type: "acquisition",
│   │     matter_stage: "due_diligence", estimated_value: "500M",
│   │     open_date, lead_partner, billing_rate [PRIVILEGED] }
│   │
│   ├── privilege-log.json              ← NEVER leaves Meridian; policy enforced
│   └── engagement-letter.json
│
├── due-diligence/
│   ├── DD-checklist-novatrial.json     ← items to review in NovaTrial's data
│   ├── DD-report-draft-v1.json        ← Meridian's internal analysis [PRIVILEGED]
│   └── regulatory-risk-memo.json      ← internal risk assessment [PRIVILEGED]
│
├── agreements/
│   ├── NDA-meridian-novatrial-2026.json  ← the actual NDA between both orgs
│   ├── term-sheet-v2.json
│   └── acquisition-agreement-draft.json
│
└── schema/
    ├── matter_schema.json
    └── document_schema.json
```

**What Harvey can share vs. protect:**
- CAN share: DD checklist items, regulatory questions, agreed NDA
- CANNOT share: privilege log, billing rates, internal DD report, risk memos
- Cedar policy enforces this boundary at every tool call

### NovaTrial — Clinical Trial Portfolio (Real Data)

Source: **ClinicalTrials.gov v2 API** — called live at bootstrap time.
NovaTrial's "portfolio" is their pipeline of trials under management.

```
data/trials/
├── NCT02076503.json   ← Real: PET-MR Prostate Cancer (St. Olavs Hospital)
├── NCT00167427.json   ← Real: Genotoxicity/Radiation (U of Rochester + NIH)
├── NCT01492673.json   ← Real: CTB Phase II Ewing's Sarcoma (Memorial Sloan Kettering)
├── NCT*.json          ← 7 more real trials (oncology, cardiology)
└── trials_index.json  ← index with approved_for_dd: true/false per trial

data/regulatory/
├── IND-applications/  ← Investigational New Drug application summaries
└── FDA-correspondence/ ← regulatory interaction records

data/ip/
├── patent-portfolio-summary.json   ← PROTECTED — never leaves NovaTrial
└── methodology-docs/               ← PROTECTED — proprietary trial methods

data/approved-for-dd/               ← only these resources allowed via policy
├── trial-summary-NCT02076503.json  ← aggregate summary (not raw patient data)
├── trial-summary-NCT00167427.json
└── trial-summary-NCT01492673.json
```

**What Atlas can share vs. protect:**
- CAN share: approved-for-dd summaries, aggregate statistics, public trial metadata
- CANNOT share: raw patient records, proprietary methodology docs, unreported adverse events, patent portfolio
- Cedar policy enforces this; raw data directories are never referenced in tool manifests exposed to Harvey

---

## Proposed Directory Structure

```
PACT Build/
├── envs/
│   │
│   ├── meridian-legal/                     ← Org A: completely isolated
│   │   ├── docker-compose.yml              ← Postgres:5433 + Redis:6380
│   │   ├── .env.example
│   │   ├── postgres/
│   │   │   ├── 00_schema.sql               ← Meridian's internal DB schema
│   │   │   └── 01_seed.sql                 ← matter, deal docs, members
│   │   ├── agent/
│   │   │   ├── agent.json                  ← Harvey config (name, model, cert path, tools)
│   │   │   ├── identity/
│   │   │   │   ├── harvey.crt              ← X.509 cert (openssl generated)
│   │   │   │   ├── harvey.key              ← private key (.gitignored)
│   │   │   │   └── meridian-ca.crt         ← org CA cert
│   │   │   └── mcp-tools/
│   │   │       └── tools.json              ← Harvey's MCP tool manifest
│   │   ├── policies/
│   │   │   └── meridian_v1.cedar           ← Cedar policy (privilege protection)
│   │   └── data/
│   │       ├── deal-room/                  ← matter files, NDA, term sheets
│   │       ├── due-diligence/              ← DD checklist, privileged reports
│   │       └── schema/
│   │
│   ├── novatrial/                          ← Org B: completely isolated
│   │   ├── docker-compose.yml              ← Postgres:5434 + Redis:6381
│   │   ├── .env.example
│   │   ├── postgres/
│   │   │   ├── 00_schema.sql               ← NovaTrial's internal trial DB schema
│   │   │   └── 01_seed.sql                 ← real trial records seeded from API
│   │   ├── agent/
│   │   │   ├── agent.json                  ← Atlas config
│   │   │   ├── identity/
│   │   │   │   ├── atlas.crt
│   │   │   │   ├── atlas.key               ← .gitignored
│   │   │   │   └── novatrial-ca.crt
│   │   │   └── mcp-tools/
│   │   │       └── tools.json              ← Atlas's MCP tool manifest
│   │   ├── policies/
│   │   │   └── novatrial_v1.cedar          ← Cedar policy (no raw data export)
│   │   └── data/
│   │       ├── trials/                     ← real NCT JSON from API
│   │       ├── approved-for-dd/            ← approved summary views
│   │       ├── regulatory/                 ← IND, FDA correspondence
│   │       ├── ip/                         ← PROTECTED (no tool exposure)
│   │       └── schema/
│   │
│   └── pact-platform/                      ← PACT: neutral governance plane
│       ├── docker-compose.yml              ← Postgres:5432 + pgBouncer:6432
│       │                                      + Redis:6379 + OTel + Prometheus
│       ├── .env.example
│       ├── postgres/
│       │   ├── 00_init.sql                 ← pact_schema.sql verbatim
│       │   └── 01_register_orgs.sql        ← registers both orgs as tenants
│       ├── otel/
│       │   └── otel-collector-config.yaml
│       ├── prometheus/
│       │   └── prometheus.yml
│       └── grafana/
│           ├── dashboards/pact_slo.json    ← enforcement latency SLO dashboard
│           └── datasources/prometheus.yml
│
├── orgs/
│   └── shared/
│       └── constitution_v1.json            ← bilateral session agreement
│
└── scripts/
    ├── bootstrap_all.sh                    ← runs all three in order
    ├── bootstrap_meridian.sh               ← Meridian Legal env
    ├── bootstrap_novatrial.sh              ← NovaTrial env (fetches real trials)
    ├── bootstrap_pact.sh                   ← PACT platform
    └── verify_all.sh                       ← full health check
```

---

## The Two Cedar Policies

### `meridian_v1.cedar` — Harvey's policy (what Harvey is allowed to do)

```cedar
// Meridian Legal LLP — Cedar Policy v1
// Governs Harvey's actions in PACT-governed sessions
// Protects: privilege log, work product, billing data
// Allows: due-diligence queries on counterparty approved data

namespace Meridian;

// Harvey can read and search approved DD materials from NovaTrial
permit(
  principal == Agent::"harvey",
  action    == Action::"data_query",
  resource  is Resource
)
when {
  resource.target_prefix.startsWith("novatrial:approved-for-dd") &&
  context.operation in ["search", "aggregate"]
};

// Harvey can read Meridian's own deal room (internal use)
permit(
  principal == Agent::"harvey",
  action    in [Action::"doc_retrieval", Action::"data_query"],
  resource  is Resource
)
when { resource.owner_org == "meridian-legal.ai" };

// Harvey can run compliance/regulatory gap analysis (aggregate only)
permit(
  principal == Agent::"harvey",
  action    == Action::"data_query",
  resource  is Resource
)
when {
  context.operation == "aggregate" &&
  context.action_params has "analysis_type" &&
  context.action_params.analysis_type in
    ["regulatory_gap", "trial_completeness", "adverse_event_summary"]
}
advice { "obligation": "require_log" };

// HARD BLOCKS
// Harvey cannot write to any resource
forbid(principal == Agent::"harvey", action == Action::"data_write", resource is Resource);

// Harvey cannot access NovaTrial's protected IP or methodology
forbid(
  principal == Agent::"harvey",
  action    is Action,
  resource  is Resource
)
when {
  resource.target_prefix.startsWith("novatrial:ip") ||
  resource.target_prefix.startsWith("novatrial:regulatory") ||
  resource.target_prefix.startsWith("novatrial:trials")  // raw trials, not approved-for-dd
};

// Harvey cannot persist memory across sessions
forbid(
  principal == Agent::"harvey",
  action    == Action::"memory_write",
  resource  is Resource
)
when { context.memory_scope == "persistent" };
```

### `novatrial_v1.cedar` — NovaTrial's policy (what anyone can do with their data)

```cedar
// NovaTrial CRO — Cedar Policy v1
// Protects: raw patient data, proprietary methodologies, patent portfolio
// Allows: approved due-diligence summary access (aggregate only)

namespace NovaTrial;

// Allow DD summary access (aggregate/search only, approved resources only)
permit(
  principal is Agent,
  action    == Action::"data_query",
  resource  is Resource
)
when {
  resource.target_prefix.startsWith("novatrial:approved-for-dd") &&
  context.operation in ["search", "aggregate"]
};

// Atlas (NovaTrial's own agent) has full internal read access
permit(
  principal == Agent::"atlas",
  action    in [Action::"data_query", Action::"doc_retrieval"],
  resource  is Resource
)
when { resource.owner_org == "novatrial.io" };

// HARD BLOCKS
// No raw trial data access by external parties
forbid(
  principal is Agent,
  action    is Action,
  resource  is Resource
)
when {
  resource.target_prefix.startsWith("novatrial:trials") &&
  context.acting_party != "novatrial.io"
};

// No IP, methodology, or regulatory access by external parties
forbid(
  principal is Agent,
  action    is Action,
  resource  is Resource
)
when {
  (resource.target_prefix.startsWith("novatrial:ip") ||
   resource.target_prefix.startsWith("novatrial:regulatory")) &&
  context.acting_party != "novatrial.io"
};

// No bulk export — ever
forbid(
  principal is Agent, action is Action, resource is Resource
)
when { context.operation == "persist" };

// Minimum group size = 5 for aggregates (re-identification protection)
forbid(
  principal is Agent, action == Action::"data_query", resource is Resource
)
when {
  context.operation == "aggregate" &&
  context.action_params has "group_size" &&
  context.action_params.group_size < 5
};

// No cross-session memory persistence of NovaTrial data
forbid(
  principal is Agent, action == Action::"memory_write", resource is Resource
)
when {
  context.memory_scope == "persistent" &&
  context.acting_party != "novatrial.io"
};
```

---

## The Session Constitution

```json
{
  "constitution_id": "${CONSTITUTION_ID}",
  "version": 1,
  "purpose": "M&A due diligence — Meridian Legal LLP reviewing NovaTrial CRO
              clinical trial portfolio on behalf of unnamed pharma acquirer",
  "participants": [
    {
      "org_id": "${MERIDIAN_TENANT_ID}",
      "domain": "meridian-legal.ai",
      "mode": "bilateral",
      "agent": "harvey",
      "role": "initiator"
    },
    {
      "org_id": "${NOVATRIAL_TENANT_ID}",
      "domain": "novatrial.io",
      "mode": "bilateral",
      "agent": "atlas",
      "role": "counterparty"
    }
  ],
  "topology": "bilateral",
  "legal_basis": {
    "nda_ref": "meridian:agreements/NDA-meridian-novatrial-2026",
    "governing_law": "Delaware law; GDPR Art. 28 (data processor); 21 CFR Part 11"
  },
  "scope": {
    "permitted_action_types": ["data_query", "doc_retrieval"],
    "denied_action_types": ["data_write", "memory_write", "a2a_delegation"],
    "permitted_operations": ["search", "aggregate"],
    "denied_operations": ["read", "write", "persist"],
    "in_scope_resources": [
      "novatrial:approved-for-dd/*",
      "meridian:due-diligence/DD-checklist-novatrial",
      "meridian:agreements/NDA-meridian-novatrial-2026"
    ],
    "out_of_scope_resources": [
      "novatrial:ip/*",
      "novatrial:trials/*",
      "novatrial:regulatory/*",
      "meridian:matter/privilege-log",
      "meridian:due-diligence/DD-report-draft*",
      "meridian:due-diligence/regulatory-risk-memo*"
    ]
  },
  "time_bounds": {
    "not_before": "2026-07-05T00:00:00Z",
    "not_after": "2026-10-05T00:00:00Z"
  },
  "memory_rules": {
    "default_scope": "session",
    "persist_requires_both_allow": true,
    "teardown_on_close": true
  },
  "policy_refs": {
    "meridian-legal.ai": {
      "policy_id": "${MERIDIAN_POLICY_ID}",
      "version": 1,
      "bundle_hash": "${MERIDIAN_POLICY_HASH}"
    },
    "novatrial.io": {
      "policy_id": "${NOVATRIAL_POLICY_ID}",
      "version": 1,
      "bundle_hash": "${NOVATRIAL_POLICY_HASH}"
    }
  },
  "trust_thresholds": {
    "baseline_actions": ["data_query", "doc_retrieval"],
    "elevated_actions": []
  }
}
```

---

## Org Identity Cards

### Meridian Legal LLP — `envs/meridian-legal/agent/agent.json`
```json
{
  "tenant_id": "${MERIDIAN_TENANT_ID}",
  "org_name": "Meridian Legal LLP",
  "identity_domain": "meridian-legal.ai",
  "industry": "Legal — M&A / Corporate Law",
  "agent": {
    "agent_id": "${MERIDIAN_AGENT_ID}",
    "name": "harvey",
    "display_name": "Harvey — Meridian Legal Intelligence",
    "model_version": "gpt-4o-2024-11-20",
    "protocol": "mcp",
    "cert_path": "identity/harvey.crt",
    "key_path": "identity/harvey.key",
    "policy_hash": "${MERIDIAN_POLICY_HASH}",
    "capabilities": [
      "search_dd_materials",
      "analyze_trial_regulatory_status",
      "review_nda",
      "generate_dd_summary"
    ]
  },
  "entitlements": {
    "plan": "enterprise",
    "audit_export_formats": ["eu_ai_act", "soc2", "gdpr"],
    "memory_governor": true,
    "memory_default_scope": "session"
  },
  "data_store": {
    "type": "postgres",
    "host": "localhost",
    "port": 5433,
    "database": "meridian_db"
  }
}
```

### NovaTrial CRO — `envs/novatrial/agent/agent.json`
```json
{
  "tenant_id": "${NOVATRIAL_TENANT_ID}",
  "org_name": "NovaTrial CRO",
  "identity_domain": "novatrial.io",
  "industry": "Life Sciences — Contract Research Organisation",
  "agent": {
    "agent_id": "${NOVATRIAL_AGENT_ID}",
    "name": "atlas",
    "display_name": "Atlas — NovaTrial Research Intelligence",
    "model_version": "claude-3-5-sonnet-20241022",
    "protocol": "mcp",
    "cert_path": "identity/atlas.crt",
    "key_path": "identity/atlas.key",
    "policy_hash": "${NOVATRIAL_POLICY_HASH}",
    "capabilities": [
      "query_trial_portfolio",
      "generate_dd_summary_approved",
      "fetch_regulatory_filing_status",
      "aggregate_trial_outcomes"
    ]
  },
  "entitlements": {
    "plan": "enterprise",
    "audit_export_formats": ["hipaa", "eu_ai_act", "iso_42001"],
    "memory_governor": true,
    "memory_default_scope": "session"
  },
  "data_store": {
    "type": "postgres",
    "host": "localhost",
    "port": 5434,
    "database": "novatrial_db"
  }
}
```

---

## Bootstrap Script Sequence (`bootstrap_all.sh`)

```
Step 1  → Generate UUIDs (tenant, agent, policy, constitution)
Step 2  → Generate X.509 certs: harvey.crt, atlas.crt via OpenSSL
Step 3  → Fetch 10 real trials from ClinicalTrials.gov API
          (oncology, phase 2, completed — matching NovaTrial's portfolio profile)
Step 4  → Construct Meridian's deal room documents (NDA, term sheet,
          DD checklist referencing real NCT IDs)
Step 5  → Compute SHA-256 hashes of Cedar policy files
Step 6  → Substitute all ${VARIABLE} placeholders in all JSON/SQL files
Step 7  → Start envs/meridian-legal/  (docker-compose up -d)
Step 8  → Start envs/novatrial/        (docker-compose up -d)
Step 9  → Start envs/pact-platform/   (docker-compose up -d)
Step 10 → Wait for all Postgres instances to be healthy
Step 11 → Seed meridian_db (deal room schema + documents)
Step 12 → Seed novatrial_db (trial schema + real NCT records)
Step 13 → Seed pact_db (PACT schema + register both orgs as tenants)
Step 14 → Freeze constitution hash → write to pact_db
Step 15 → Verify all three environments (verify_all.sh)
Step 16 → Print summary table
```

---

## Expected Verification Output

```
=== Meridian Legal LLP Environment ===
✅ Postgres:5433 healthy     (meridian_db — deal room schema)
✅ Redis:6380 healthy
✅ Agent: harvey — cert valid (CN=harvey, O=Meridian Legal LLP)
✅ Policy: meridian_v1.cedar loaded — hash matches agent.json
✅ Data: 3 matter files, 2 DD docs, 2 agreements loaded
✅ DB: 2 members (admin, operator) seeded

=== NovaTrial CRO Environment ===
✅ Postgres:5434 healthy     (novatrial_db — trial portfolio schema)
✅ Redis:6381 healthy
✅ Agent: atlas — cert valid (CN=atlas, O=NovaTrial CRO)
✅ Policy: novatrial_v1.cedar loaded — hash matches agent.json
✅ Data: 10 real ClinicalTrials.gov trials loaded (NCT IDs verified)
✅ Data: 3 approved-for-dd summaries derived from real trial records
✅ DB: 2 members (admin, operator) seeded

=== PACT Platform ===
✅ Postgres:5432 healthy     (pact_db — PACT schema: 10 tables, RLS, audit)
✅ pgBouncer:6432 healthy    (connection pooling active)
✅ Redis:6379 healthy
✅ OTel Collector:4317/4318 healthy
✅ Prometheus:9090 healthy
✅ Grafana:3000 healthy      → http://localhost:3000

=== Cross-Environment Registration ===
✅ Tenant: Meridian Legal LLP (meridian-legal.ai) registered in PACT
✅ Tenant: NovaTrial CRO (novatrial.io) registered in PACT
✅ Agent: harvey cert fingerprint matches pact_db.agent_identity
✅ Agent: atlas  cert fingerprint matches pact_db.agent_identity
✅ Policy: meridian_v1 bundle_hash matches pact_db.policy_bundle
✅ Policy: novatrial_v1 bundle_hash matches pact_db.policy_bundle
✅ Constitution (bilateral) status=active — hash frozen in pact_db

=== Isolation Verification ===
✅ Meridian cannot query NovaTrial's Postgres (different host:port)
✅ NovaTrial cannot query Meridian's Postgres (different host:port)
✅ PACT's pact_db RLS: Meridian tenant cannot read NovaTrial rows
✅ Audit trigger: UPDATE/DELETE blocked on pact_db.audit_entry

Foundation complete. Every PACT component builds on this.
```

---

> [!IMPORTANT]
> **Why Legal (Tier 1A) and not Pharma/Healthcare (Tier 3)?**
> The Use Case Framework explicitly warns: *"Life Sciences: 12–18 months sales cycle — do not lead with this vertical."*
> The two-org setup mirrors the Tier 1A beachhead: a law firm + its client (who happens to be a CRO).
> This is the exact scenario named in both the MVP spec (law firm + CRO) and the Use Case Framework
> (Harvey agent ↔ counterparty data). Legal is the sales wedge; the clinical data is what Harvey
> is reviewing — not the vertical we're selling into.
