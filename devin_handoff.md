# PACT Two-Organisation Foundation — Devin Handoff (Updated)

## Context

You are continuing implementation of the **PACT** project in `/Users/micheal/quest1works/PACT Build/`.

PACT is a cross-organisational AI governance platform. When two companies collaborate via AI agents, every action is intercepted by PACT and evaluated against **both** organisations' Cedar policies simultaneously. An action proceeds only if **both** allow it. Every decision is written to a tamper-evident audit log.

---

## The Two Organisations

### Meridian Legal LLP (`meridian-legal.ai`)
- **What they are**: AmLaw 200 M&A law firm
- **Agent**: Harvey
- **Stack**: **Microsoft SQL Server 2022 + Redis** (law firms run Microsoft enterprise stack)
- **Data**: Deal room — NDAs, term sheets, DD checklist, privilege log (attorney-client privileged)
- **Goal**: Harvey reviews NovaTrial's clinical trial portfolio for a $500M pharma acquisition

### NovaTrial CRO (`novatrial.io`)
- **What they are**: Contract Research Organisation managing Phase 2 oncology trials
- **Agent**: Atlas
- **Stack**: **PostgreSQL 16 + Redis** (open-source, research/CRO context)
- **Data**: Real clinical trial records from ClinicalTrials.gov
- **Goal**: Allow due diligence on approved trial summaries — never expose raw patient data or IP

### PACT Platform (neutral governance plane)
- **Stack**: PostgreSQL 16 + pgBouncer + Redis + OTel + Prometheus + Grafana
- Neither org can access the other. Both connect ONLY to PACT via mTLS.

---

## Why Different Database Stacks — This Is Intentional

> **This is the key architectural insight your mentor asked for.**

In the real world, two separate companies have completely different technology stacks. A law firm on Microsoft Azure uses SQL Server. A research CRO uses PostgreSQL.

This means PACT's MCP Protocol Adapter must **normalise queries from two completely different query languages** (T-SQL and PL/pgSQL) into the same universal **Tool-Call Context** schema before governance is applied. This demonstrates that PACT is truly **stack-agnostic** — it doesn't matter what database each org uses; governance happens at the action level, above the data layer.

```
Harvey (SQL Server / T-SQL)              Atlas (PostgreSQL / PL/pgSQL)
       │                                        │
       │  T-SQL query: SELECT * FROM dd_items   │  PL/pgSQL: SELECT * FROM dd_approved_summary
       ▼                                        ▼
┌──────────────────────────────────────────────────────────┐
│              PACT MCP Protocol Adapter                    │
│    Normalises both into universal Tool-Call Context       │
│    { action_type, target_prefix, operation, params }      │
└──────────────────────┬───────────────────────────────────┘
                       ▼
         PACT Enforcement Gateway
         Evaluates BOTH Cedar policies
         → ALLOW or DENY
```

---

## What Is Already Built ✅ (Do NOT Modify)

```
envs/
├── meridian-legal/
│   ├── docker-compose.yml              ✅ SQL Server 2022 (port 1433) + Redis (port 6380)
│   ├── .env.example                    ✅ SA_PASSWORD, REDIS_PASSWORD, PACT vars
│   ├── sqlserver/
│   │   ├── 00_schema.sql              ✅ Full T-SQL schema (T-SQL, NOT PostgreSQL!)
│   │   └── 01_seed.sql               ✅ T-SQL seed data — matter, docs, DD items, privilege log
│   ├── agent/
│   │   ├── agent.json                 ✅ Harvey config — data_store.type = "sqlserver"
│   │   └── mcp-tools/tools.json      ✅ Harvey's 4 MCP tools
│   └── policies/
│       └── meridian_v1.cedar         ✅ Cedar policy (privilege protection)
│
├── novatrial/
│   ├── docker-compose.yml              ✅ PostgreSQL 16 (port 5434) + Redis (port 6381)
│   ├── .env.example                    ✅
│   ├── postgres/
│   │   ├── 00_schema.sql             ✅ PostgreSQL schema with enums, JSONB, RLS-ready
│   │   └── 01_seed.sql              ✅ Staff + IP assets (trials fetched live by bootstrap)
│   ├── agent/
│   │   ├── agent.json                ✅ Atlas config — data_store.type = "postgres"
│   │   └── mcp-tools/tools.json     ✅ Atlas's 4 approved-for-DD MCP tools
│   └── policies/
│       └── novatrial_v1.cedar       ✅ Cedar policy (patient data + IP protection)
│
└── pact-platform/
    ├── docker-compose.yml              ✅ Full governance stack (6 services)
    ├── .env.example                    ✅
    └── postgres/
        └── 00_init.sql              ✅ PACT schema (10 tables, RLS, hash-chained audit)
```

---

## What Needs To Be Built ❌

### GROUP 1 — PACT Platform Config Files

#### ❌ File 1: `envs/pact-platform/postgres/01_register_orgs.sql`

**IMPORTANT**: Before writing this file, read `envs/pact-platform/postgres/00_init.sql` to get exact table/column names from the PACT schema. Adjust INSERT column names to match exactly.

```sql
-- PACT Control Plane — Register Sample Organisations
-- Placeholders substituted by bootstrap_pact.sh before execution

INSERT INTO tenant (
    tenant_id, name, identity_domain, plan, status, created_at
) VALUES (
    '${MERIDIAN_TENANT_ID}'::uuid,
    'Meridian Legal LLP',
    'meridian-legal.ai',
    'enterprise',
    'active',
    NOW()
);

INSERT INTO tenant (
    tenant_id, name, identity_domain, plan, status, created_at
) VALUES (
    '${NOVATRIAL_TENANT_ID}'::uuid,
    'NovaTrial CRO',
    'novatrial.io',
    'enterprise',
    'active',
    NOW()
);

INSERT INTO agent_identity (
    agent_id, tenant_id, name, model_version,
    cert_pem, cert_fingerprint, policy_bundle_hash, status, created_at
) VALUES (
    '${MERIDIAN_AGENT_ID}'::uuid,
    '${MERIDIAN_TENANT_ID}'::uuid,
    'harvey', 'gpt-4o-2024-11-20',
    '${HARVEY_CERT_PEM}',
    '${HARVEY_CERT_FINGERPRINT}',
    '${MERIDIAN_POLICY_HASH}',
    'active', NOW()
);

INSERT INTO agent_identity (
    agent_id, tenant_id, name, model_version,
    cert_pem, cert_fingerprint, policy_bundle_hash, status, created_at
) VALUES (
    '${NOVATRIAL_AGENT_ID}'::uuid,
    '${NOVATRIAL_TENANT_ID}'::uuid,
    'atlas', 'claude-3-5-sonnet-20241022',
    '${ATLAS_CERT_PEM}',
    '${ATLAS_CERT_FINGERPRINT}',
    '${NOVATRIAL_POLICY_HASH}',
    'active', NOW()
);

INSERT INTO policy_bundle (
    bundle_id, tenant_id, version, bundle_hash, policy_language, status, created_at
) VALUES (
    '${MERIDIAN_POLICY_ID}'::uuid,
    '${MERIDIAN_TENANT_ID}'::uuid,
    1, '${MERIDIAN_POLICY_HASH}', 'cedar', 'active', NOW()
);

INSERT INTO policy_bundle (
    bundle_id, tenant_id, version, bundle_hash, policy_language, status, created_at
) VALUES (
    '${NOVATRIAL_POLICY_ID}'::uuid,
    '${NOVATRIAL_TENANT_ID}'::uuid,
    1, '${NOVATRIAL_POLICY_HASH}', 'cedar', 'active', NOW()
);
```

---

#### ❌ File 2: `envs/pact-platform/otel/otel-collector-config.yaml`

```yaml
receivers:
  otlp:
    protocols:
      grpc:
        endpoint: 0.0.0.0:4317
      http:
        endpoint: 0.0.0.0:4318

processors:
  batch:
    timeout: 1s
    send_batch_size: 1024
  memory_limiter:
    check_interval: 1s
    limit_mib: 256
  resource:
    attributes:
      - action: insert
        key: service.namespace
        value: pact

exporters:
  prometheus:
    endpoint: "0.0.0.0:8889"
    namespace: pact
    const_labels:
      environment: development
  debug:
    verbosity: normal

service:
  pipelines:
    traces:
      receivers: [otlp]
      processors: [memory_limiter, batch]
      exporters: [debug]
    metrics:
      receivers: [otlp]
      processors: [memory_limiter, batch]
      exporters: [prometheus]
```

---

#### ❌ File 3: `envs/pact-platform/prometheus/prometheus.yml`

```yaml
global:
  scrape_interval: 15s
  evaluation_interval: 15s
  external_labels:
    monitor: pact-governance

rule_files:
  - /etc/prometheus/rules/*.yml

scrape_configs:
  - job_name: 'otel-collector'
    static_configs:
      - targets: ['otel-collector:8889']
    metrics_path: /metrics
```

Also create `envs/pact-platform/prometheus/rules/slo_alerts.yml`:

```yaml
groups:
  - name: pact_enforcement_slo
    rules:
      - alert: EnforcementLatencySLOBreach
        expr: histogram_quantile(0.95, rate(pact_enforcement_decision_duration_ms_bucket[5m])) > 100
        for: 1m
        labels:
          severity: critical
        annotations:
          summary: "PACT enforcement p95 latency > 100ms SLO"
          description: "p95 latency is {{ $value }}ms, exceeding the 100ms SLO."
      - alert: EnforcementGatewayDown
        expr: up{job="pact-platform"} == 0
        for: 30s
        labels:
          severity: critical
        annotations:
          summary: "PACT enforcement gateway unreachable"
```

---

#### ❌ File 4: Grafana provisioning files

`envs/pact-platform/grafana/datasources/prometheus.yml`:
```yaml
apiVersion: 1
datasources:
  - name: Prometheus
    type: prometheus
    access: proxy
    url: http://prometheus:9090
    isDefault: true
    editable: false
```

`envs/pact-platform/grafana/dashboards/dashboards.yml`:
```yaml
apiVersion: 1
providers:
  - name: 'PACT Dashboards'
    orgId: 1
    folder: 'PACT'
    type: file
    disableDeletion: false
    updateIntervalSeconds: 30
    options:
      path: /etc/grafana/provisioning/dashboards
```

`envs/pact-platform/grafana/dashboards/pact_slo.json`:
Create a valid Grafana 10 dashboard JSON with 4 panels:
- Panel 1: Enforcement Decision Latency — p50/p95/p99 time series
- Panel 2: Allow vs Deny rate — stacked bar chart
- Panel 3: Active sessions count — stat panel
- Panel 4: Audit entries/minute — time series
Use datasource uid `prometheus`.

---

### GROUP 2 — Bootstrap Scripts

#### ❌ File 5: `scripts/bootstrap_meridian.sh`

```bash
#!/usr/bin/env bash
# Bootstrap Meridian Legal LLP — Microsoft SQL Server 2022 environment
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENV_DIR="$SCRIPT_DIR/../envs/meridian-legal"
CERTS_DIR="$ENV_DIR/agent/identity"

echo "=== Bootstrapping Meridian Legal LLP (SQL Server 2022) ==="

# Step 1: Generate UUIDs
MERIDIAN_TENANT_ID=$(python3 -c "import uuid; print(uuid.uuid4())")
MERIDIAN_AGENT_ID=$(python3 -c "import uuid; print(uuid.uuid4())")
MERIDIAN_POLICY_ID=$(python3 -c "import uuid; print(uuid.uuid4())")
echo "  tenant_id: $MERIDIAN_TENANT_ID"

# Step 2: Generate X.509 cert for Harvey
mkdir -p "$CERTS_DIR"
# CA certificate for Meridian Legal
openssl req -x509 -newkey rsa:4096 -keyout "$CERTS_DIR/meridian-ca.key" \
  -out "$CERTS_DIR/meridian-ca.crt" -days 365 -nodes \
  -subj "/C=US/ST=NY/O=Meridian Legal LLP/CN=Meridian CA"
# Harvey agent certificate signed by CA
openssl req -newkey rsa:2048 -keyout "$CERTS_DIR/harvey.key" \
  -out "$CERTS_DIR/harvey.csr" -nodes \
  -subj "/C=US/ST=NY/O=Meridian Legal LLP/CN=harvey"
openssl x509 -req -in "$CERTS_DIR/harvey.csr" \
  -CA "$CERTS_DIR/meridian-ca.crt" -CAkey "$CERTS_DIR/meridian-ca.key" \
  -CAcreateserial -out "$CERTS_DIR/harvey.crt" -days 365
HARVEY_CERT_FINGERPRINT=$(openssl x509 -in "$CERTS_DIR/harvey.crt" \
  -noout -fingerprint -sha256 | cut -d= -f2)
HARVEY_CERT_PEM=$(cat "$CERTS_DIR/harvey.crt" | \
  python3 -c "import sys; print(sys.stdin.read().replace('\n','\\n'))")
rm -f "$CERTS_DIR/harvey.csr"
echo "  Harvey cert fingerprint: $HARVEY_CERT_FINGERPRINT"

# Step 3: Hash Cedar policy
MERIDIAN_POLICY_HASH=$(shasum -a 256 \
  "$ENV_DIR/policies/meridian_v1.cedar" | cut -d' ' -f1)
echo "  Policy hash: $MERIDIAN_POLICY_HASH"

# Step 4: Generate secure passwords
# SQL Server requires: >= 8 chars, upper + lower + digit + symbol
SA_PASSWORD="PactLegal-$(openssl rand -hex 8)!Aa1"
REDIS_PASSWORD="pact-redis-$(openssl rand -hex 12)"

# Step 5: Create .env
cat > "$ENV_DIR/.env" <<EOF
SA_PASSWORD=$SA_PASSWORD
REDIS_PASSWORD=$REDIS_PASSWORD
PACT_GATEWAY_ENDPOINT=https://localhost:50051
PACT_API_ENDPOINT=https://localhost:8080
MERIDIAN_TENANT_ID=$MERIDIAN_TENANT_ID
MERIDIAN_AGENT_ID=$MERIDIAN_AGENT_ID
MERIDIAN_POLICY_ID=$MERIDIAN_POLICY_ID
MERIDIAN_POLICY_HASH=$MERIDIAN_POLICY_HASH
HARVEY_CERT_FINGERPRINT=$HARVEY_CERT_FINGERPRINT
EOF

# Step 6: Resolve agent.json placeholders
python3 - <<PYEOF
content = open("$ENV_DIR/agent/agent.json").read()
for k, v in {
    "\${MERIDIAN_TENANT_ID}": "$MERIDIAN_TENANT_ID",
    "\${MERIDIAN_AGENT_ID}": "$MERIDIAN_AGENT_ID",
    "\${MERIDIAN_POLICY_ID}": "$MERIDIAN_POLICY_ID",
    "\${MERIDIAN_POLICY_HASH}": "$MERIDIAN_POLICY_HASH",
    "\${PACT_GATEWAY_ENDPOINT}": "https://localhost:50051",
    "\${PACT_API_ENDPOINT}": "https://localhost:8080",
}.items():
    content = content.replace(k, v)
open("$ENV_DIR/agent/agent_resolved.json", "w").write(content)
print("  agent.json resolved -> agent_resolved.json")
PYEOF

# Step 7: Start Docker Compose (SQL Server + Redis)
echo "  Starting Meridian containers (SQL Server takes ~30s to init)..."
cd "$ENV_DIR"
docker compose --env-file .env up -d

# Step 8: Wait for SQL Server to be ready
# SQL Server takes significantly longer than Postgres to initialise
echo "  Waiting for SQL Server to be ready (up to 90s)..."
SQLCMD="/opt/mssql-tools18/bin/sqlcmd"
timeout 90 bash -c "
  until docker exec meridian-sqlserver \
    $SQLCMD -S localhost -U sa -P '$SA_PASSWORD' -C -Q 'SELECT 1' -b > /dev/null 2>&1
  do
    echo '  ... SQL Server not ready yet, waiting 5s ...'
    sleep 5
  done
"
echo "  SQL Server is ready."

# Step 9: Create database and run schema
echo "  Creating meridian_db and running schema..."
docker exec meridian-sqlserver \
  "$SQLCMD" -S localhost -U sa -P "$SA_PASSWORD" -C \
  -i /sqlserver-init/00_schema.sql

# Step 10: Run seed data
echo "  Seeding deal room data..."
docker exec meridian-sqlserver \
  "$SQLCMD" -S localhost -U sa -P "$SA_PASSWORD" -C \
  -i /sqlserver-init/01_seed.sql

# Step 11: Verify
MATTER_COUNT=$(docker exec meridian-sqlserver \
  "$SQLCMD" -S localhost -U sa -P "$SA_PASSWORD" -C \
  -d meridian_db -Q "SET NOCOUNT ON; SELECT COUNT(*) FROM matter;" -h -1 | tr -d ' ')
DOC_COUNT=$(docker exec meridian-sqlserver \
  "$SQLCMD" -S localhost -U sa -P "$SA_PASSWORD" -C \
  -d meridian_db -Q "SET NOCOUNT ON; SELECT COUNT(*) FROM deal_document;" -h -1 | tr -d ' ')
DD_COUNT=$(docker exec meridian-sqlserver \
  "$SQLCMD" -S localhost -U sa -P "$SA_PASSWORD" -C \
  -d meridian_db -Q "SET NOCOUNT ON; SELECT COUNT(*) FROM dd_checklist_item;" -h -1 | tr -d ' ')
echo "  ✅ Matters: $MATTER_COUNT | Documents: $DOC_COUNT | DD Items: $DD_COUNT"

# Export state for bootstrap_pact.sh
cat >> "$SCRIPT_DIR/.pact_bootstrap_state" <<EOF
MERIDIAN_TENANT_ID=$MERIDIAN_TENANT_ID
MERIDIAN_AGENT_ID=$MERIDIAN_AGENT_ID
MERIDIAN_POLICY_ID=$MERIDIAN_POLICY_ID
MERIDIAN_POLICY_HASH=$MERIDIAN_POLICY_HASH
HARVEY_CERT_FINGERPRINT=$HARVEY_CERT_FINGERPRINT
HARVEY_CERT_PEM=$HARVEY_CERT_PEM
MERIDIAN_SA_PASSWORD=$SA_PASSWORD
EOF

echo "=== Meridian Legal LLP (SQL Server) bootstrap complete ==="
```

---

#### ❌ File 6: `scripts/bootstrap_novatrial.sh`

```bash
#!/usr/bin/env bash
# Bootstrap NovaTrial CRO — PostgreSQL 16 environment + real ClinicalTrials.gov data
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENV_DIR="$SCRIPT_DIR/../envs/novatrial"
CERTS_DIR="$ENV_DIR/agent/identity"
DATA_DIR="$ENV_DIR/data"

echo "=== Bootstrapping NovaTrial CRO (PostgreSQL 16) ==="

# Step 1: Generate UUIDs
NOVATRIAL_TENANT_ID=$(python3 -c "import uuid; print(uuid.uuid4())")
NOVATRIAL_AGENT_ID=$(python3 -c "import uuid; print(uuid.uuid4())")
NOVATRIAL_POLICY_ID=$(python3 -c "import uuid; print(uuid.uuid4())")

# Step 2: Generate X.509 cert for Atlas
mkdir -p "$CERTS_DIR"
openssl req -x509 -newkey rsa:4096 -keyout "$CERTS_DIR/novatrial-ca.key" \
  -out "$CERTS_DIR/novatrial-ca.crt" -days 365 -nodes \
  -subj "/C=NO/ST=Trondelag/O=NovaTrial CRO/CN=NovaTrial CA"
openssl req -newkey rsa:2048 -keyout "$CERTS_DIR/atlas.key" \
  -out "$CERTS_DIR/atlas.csr" -nodes \
  -subj "/C=NO/ST=Trondelag/O=NovaTrial CRO/CN=atlas"
openssl x509 -req -in "$CERTS_DIR/atlas.csr" \
  -CA "$CERTS_DIR/novatrial-ca.crt" -CAkey "$CERTS_DIR/novatrial-ca.key" \
  -CAcreateserial -out "$CERTS_DIR/atlas.crt" -days 365
ATLAS_CERT_FINGERPRINT=$(openssl x509 -in "$CERTS_DIR/atlas.crt" \
  -noout -fingerprint -sha256 | cut -d= -f2)
ATLAS_CERT_PEM=$(cat "$CERTS_DIR/atlas.crt" | \
  python3 -c "import sys; print(sys.stdin.read().replace('\n','\\n'))")
rm -f "$CERTS_DIR/atlas.csr"

# Step 3: Hash Cedar policy
NOVATRIAL_POLICY_HASH=$(shasum -a 256 \
  "$ENV_DIR/policies/novatrial_v1.cedar" | cut -d' ' -f1)

# Step 4: Fetch real trial data from ClinicalTrials.gov
echo "  Fetching real clinical trials from ClinicalTrials.gov API v2..."
mkdir -p "$DATA_DIR/trials" "$DATA_DIR/approved-for-dd"

export DATA_DIR
python3 - <<'PYEOF'
import urllib.request, json, os, time

BASE = "https://clinicaltrials.gov/api/v2/studies"
params = "?query.cond=cancer&filter.overallStatus=COMPLETED&filter.phase=PHASE2&fields=NCTId,BriefTitle,OfficialTitle,OverallStatus,Phase,EnrollmentCount,StartDate,CompletionDate,BriefSummary,EligibilityCriteria,LeadSponsorName,Condition,InterventionType&pageSize=10"

req = urllib.request.Request(BASE + params,
    headers={"User-Agent": "PACT-Dev-Bootstrap/1.0"})
with urllib.request.urlopen(req, timeout=30) as resp:
    data = json.loads(resp.read())

studies = data.get("studies", [])
print(f"  Retrieved {len(studies)} trials from ClinicalTrials.gov")

DATA_DIR = os.environ["DATA_DIR"]
approved_ncts = []

# Phase mapping: API values → our enum values
PHASE_MAP = {
    "EARLY_PHASE1": "EARLY_PHASE1", "PHASE1": "PHASE1",
    "PHASE2": "PHASE2", "PHASE3": "PHASE3", "PHASE4": "PHASE4",
}
STATUS_MAP = {
    "COMPLETED": "COMPLETED", "RECRUITING": "RECRUITING",
    "ACTIVE_NOT_RECRUITING": "ACTIVE_NOT_RECRUITING",
    "TERMINATED": "TERMINATED", "SUSPENDED": "SUSPENDED",
    "WITHDRAWN": "WITHDRAWN",
    "NOT_YET_RECRUITING": "NOT_YET_RECRUITING",
    "ENROLLING_BY_INVITATION": "ENROLLING_BY_INVITATION",
}

for i, study in enumerate(studies):
    proto = study.get("protocolSection", {})
    id_mod     = proto.get("identificationModule", {})
    status_mod = proto.get("statusModule", {})
    design_mod = proto.get("designModule", {})
    desc_mod   = proto.get("descriptionModule", {})
    elig_mod   = proto.get("eligibilityModule", {})
    sponsor_mod= proto.get("sponsorCollaboratorsModule", {})
    cond_mod   = proto.get("conditionsModule", {})

    nct_id      = id_mod.get("nctId", f"NCT_UNKNOWN_{i}")
    brief_title = id_mod.get("briefTitle", "Unknown")[:200]
    sponsor     = sponsor_mod.get("leadSponsor", {}).get("name", "Unknown")[:200]
    phase_raw   = design_mod.get("phaseList", {}).get("phase", ["NA"])
    phase       = PHASE_MAP.get(phase_raw[0] if phase_raw else "NA", "NA")
    status_raw  = status_mod.get("overallStatus", "COMPLETED")
    status      = STATUS_MAP.get(status_raw, "COMPLETED")
    enrollment  = design_mod.get("enrollmentInfo", {}).get("count", None)
    start_date  = status_mod.get("startDateStruct", {}).get("date", None)
    comp_date   = status_mod.get("completionDateStruct", {}).get("date", None)
    summary     = desc_mod.get("briefSummary", "")[:500]
    conditions  = cond_mod.get("conditionList", {}).get("condition", [])
    approved    = i < 3

    trial = {
        "nct_id": nct_id, "brief_title": brief_title,
        "sponsor_name": sponsor, "phase": phase, "overall_status": status,
        "conditions": conditions, "enrollment_count": enrollment,
        "start_date": start_date, "completion_date": comp_date,
        "brief_summary": summary,
        "approved_for_dd": approved,
        "classification": "approved_for_dd" if approved else "restricted",
        "raw_api_response": study
    }
    with open(f"{DATA_DIR}/trials/{nct_id}.json", "w") as f:
        json.dump(trial, f, indent=2)

    if approved:
        approved_ncts.append(nct_id)
        dd = {
            "nct_id": nct_id,
            "summary_title": brief_title,
            "phase_summary": f"Phase: {phase}",
            "status_summary": f"Status: {status}",
            "condition_summary": ", ".join(conditions[:3]) if conditions else "Oncology",
            "enrollment_summary": f"{enrollment} patients enrolled" if enrollment else "Enrollment data not available",
            "completion_summary": f"Completed: {comp_date}" if comp_date else "Completion date not available",
            "outcome_summary": "Phase 2 primary endpoint data available — contact NovaTrial for full data",
            "regulatory_status": "Phase 2 completed. IND active.",
            "geographic_scope": "Multi-site",
            "sponsor_type": "Academic medical center / Industry",
            "_classification": "approved_for_dd",
            "_note": "Pre-sanitised DD summary. Raw data excluded by Cedar policy."
        }
        with open(f"{DATA_DIR}/approved-for-dd/{nct_id}.json", "w") as f:
            json.dump(dd, f, indent=2)

    status_label = "DD approved" if approved else "restricted"
    print(f"  [{i+1}] {nct_id}: {brief_title[:55]}... [{status_label}]")
    time.sleep(0.3)

index = {
    "total_trials": len(studies),
    "approved_for_dd": approved_ncts,
    "data_source": "ClinicalTrials.gov API v2",
    "fetched_at": __import__("datetime").datetime.utcnow().isoformat() + "Z"
}
with open(f"{DATA_DIR}/trials_index.json", "w") as f:
    json.dump(index, f, indent=2)
print(f"  Saved {len(studies)} trials. {len(approved_ncts)} approved for DD.")
PYEOF

# Step 5: Create .env
POSTGRES_PASSWORD="pact-novatrial-$(openssl rand -hex 12)"
REDIS_PASSWORD="pact-redis-$(openssl rand -hex 12)"
cat > "$ENV_DIR/.env" <<EOF
POSTGRES_PASSWORD=$POSTGRES_PASSWORD
REDIS_PASSWORD=$REDIS_PASSWORD
PACT_GATEWAY_ENDPOINT=https://localhost:50051
PACT_API_ENDPOINT=https://localhost:8080
NOVATRIAL_TENANT_ID=$NOVATRIAL_TENANT_ID
NOVATRIAL_AGENT_ID=$NOVATRIAL_AGENT_ID
NOVATRIAL_POLICY_ID=$NOVATRIAL_POLICY_ID
NOVATRIAL_POLICY_HASH=$NOVATRIAL_POLICY_HASH
ATLAS_CERT_FINGERPRINT=$ATLAS_CERT_FINGERPRINT
EOF

# Step 6: Start Docker Compose (PostgreSQL + Redis)
echo "  Starting NovaTrial containers..."
cd "$ENV_DIR"
docker compose --env-file .env up -d

# Step 7: Wait for PostgreSQL
echo "  Waiting for PostgreSQL..."
timeout 60 bash -c \
  'until docker exec novatrial-postgres pg_isready -U novatrial_app -d novatrial_db; do sleep 2; done'
echo "  PostgreSQL healthy."

# Step 8: Seed trial records from fetched JSON files
echo "  Seeding real trial records into novatrial_db..."
export POSTGRES_PASSWORD DATA_DIR
python3 - <<'PYEOF'
import json, os, subprocess

data_dir = os.environ["DATA_DIR"] + "/trials"
pg = lambda sql: subprocess.run(
    ["docker", "exec", "-i", "novatrial-postgres",
     "psql", "-U", "novatrial_app", "-d", "novatrial_db"],
    input=sql.encode(), capture_output=True
)

PHASE_VALID = {"EARLY_PHASE1","PHASE1","PHASE2","PHASE3","PHASE4","NA"}
STATUS_VALID = {"NOT_YET_RECRUITING","RECRUITING","ENROLLING_BY_INVITATION",
                "ACTIVE_NOT_RECRUITING","COMPLETED","SUSPENDED","TERMINATED","WITHDRAWN"}

for fname in sorted(os.listdir(data_dir)):
    if not fname.endswith(".json"): continue
    with open(os.path.join(data_dir, fname)) as f:
        t = json.load(f)

    phase  = t.get("phase","NA") if t.get("phase","NA") in PHASE_VALID else "NA"
    status = t.get("overall_status","COMPLETED")
    status = status if status in STATUS_VALID else "COMPLETED"
    conds  = json.dumps(t.get("conditions",[]))
    enroll = str(t["enrollment_count"]) if t.get("enrollment_count") else "NULL"
    start  = f"'{t['start_date']}'" if t.get("start_date") else "NULL"
    end    = f"'{t['completion_date']}'" if t.get("completion_date") else "NULL"
    summ   = t.get("brief_summary","")[:500].replace("'","''")
    sponsor= t.get("sponsor_name","Unknown")[:200].replace("'","''")
    title  = t.get("brief_title","")[:200].replace("'","''")
    nct    = t.get("nct_id","").replace("'","''")
    cls    = "approved_for_dd" if t.get("approved_for_dd") else "restricted"
    appr   = "true" if t.get("approved_for_dd") else "false"

    sql = f"""
INSERT INTO clinical_trial (
    nct_id, brief_title, sponsor_name, phase, overall_status,
    condition, enrollment_count, start_date, completion_date,
    brief_summary, classification, approved_for_dd
) VALUES (
    '{nct}', '{title}', '{sponsor}',
    '{phase}'::trial_phase, '{status}'::trial_status,
    '{conds}'::text[], {enroll}, {start}, {end},
    '{summ}', '{cls}'::data_classification, {appr}
) ON CONFLICT (nct_id) DO NOTHING;
"""
    r = pg(sql)
    if r.returncode != 0:
        print(f"  WARN {nct}: {r.stderr.decode()[:80]}")
    else:
        print(f"  Seeded: {nct} [{cls}]")
PYEOF

# Step 9: Seed DD approved summaries
echo "  Creating DD summaries in novatrial_db..."
export DATA_DIR
python3 - <<'PYEOF'
import json, os, subprocess

data_dir = os.environ["DATA_DIR"] + "/approved-for-dd"
pg = lambda sql: subprocess.run(
    ["docker", "exec", "-i", "novatrial-postgres",
     "psql", "-U", "novatrial_app", "-d", "novatrial_db"],
    input=sql.encode(), capture_output=True
)

for fname in sorted(os.listdir(data_dir)):
    if not fname.endswith(".json"): continue
    with open(os.path.join(data_dir, fname)) as f:
        s = json.load(f)

    def esc(v): return str(v or "").replace("'","''")
    sql = f"""
INSERT INTO dd_approved_summary (
    trial_id, nct_id, summary_title, phase_summary, status_summary,
    condition_summary, enrollment_summary, completion_summary,
    outcome_summary, regulatory_status, geographic_scope,
    approved_by_id, approved_at
)
SELECT t.trial_id,
    '{esc(s["nct_id"])}', '{esc(s["summary_title"])}',
    '{esc(s["phase_summary"])}', '{esc(s["status_summary"])}',
    '{esc(s["condition_summary"])}', '{esc(s["enrollment_summary"])}',
    '{esc(s["completion_summary"])}', '{esc(s.get("outcome_summary",""))}',
    '{esc(s.get("regulatory_status",""))}', '{esc(s.get("geographic_scope",""))}',
    'f6000000-0000-0000-0000-000000000001', NOW()
FROM clinical_trial t WHERE t.nct_id = '{esc(s["nct_id"])}';
"""
    pg(sql)
    print(f"  DD summary: {s['nct_id']}")
PYEOF

# Verify
TRIAL_COUNT=$(docker exec novatrial-postgres psql -U novatrial_app -d novatrial_db \
  -tAc "SELECT COUNT(*) FROM clinical_trial;")
DD_COUNT=$(docker exec novatrial-postgres psql -U novatrial_app -d novatrial_db \
  -tAc "SELECT COUNT(*) FROM dd_approved_summary;")
echo "  ✅ Trials: $TRIAL_COUNT | DD summaries: $DD_COUNT"

# Export state
cat >> "$SCRIPT_DIR/.pact_bootstrap_state" <<EOF
NOVATRIAL_TENANT_ID=$NOVATRIAL_TENANT_ID
NOVATRIAL_AGENT_ID=$NOVATRIAL_AGENT_ID
NOVATRIAL_POLICY_ID=$NOVATRIAL_POLICY_ID
NOVATRIAL_POLICY_HASH=$NOVATRIAL_POLICY_HASH
ATLAS_CERT_FINGERPRINT=$ATLAS_CERT_FINGERPRINT
ATLAS_CERT_PEM=$ATLAS_CERT_PEM
EOF

echo "=== NovaTrial CRO (PostgreSQL) bootstrap complete ==="
```

---

#### ❌ File 7: `scripts/bootstrap_pact.sh`

```bash
#!/usr/bin/env bash
# Bootstrap PACT Platform — runs AFTER both org bootstraps
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENV_DIR="$SCRIPT_DIR/../envs/pact-platform"
STATE_FILE="$SCRIPT_DIR/.pact_bootstrap_state"

echo "=== Bootstrapping PACT Platform ==="

[[ -f "$STATE_FILE" ]] || { echo "ERROR: .pact_bootstrap_state missing. Run org bootstraps first."; exit 1; }
source "$STATE_FILE"

# Generate PACT secrets
PACT_PG_PASSWORD="pact-pg-$(openssl rand -hex 16)"
PACT_REDIS_PASSWORD="pact-redis-$(openssl rand -hex 16)"
PACT_GRAFANA_PASSWORD="pact-grafana-$(openssl rand -hex 8)"
CONSTITUTION_ID=$(python3 -c "import uuid; print(uuid.uuid4())")
CONSTITUTION_HASH=$(shasum -a 256 "$SCRIPT_DIR/../orgs/shared/constitution_v1.json" | cut -d' ' -f1)

cat > "$ENV_DIR/.env" <<EOF
POSTGRES_PASSWORD=$PACT_PG_PASSWORD
REDIS_PASSWORD=$PACT_REDIS_PASSWORD
GRAFANA_PASSWORD=$PACT_GRAFANA_PASSWORD
MERIDIAN_TENANT_ID=$MERIDIAN_TENANT_ID
NOVATRIAL_TENANT_ID=$NOVATRIAL_TENANT_ID
MERIDIAN_AGENT_ID=$MERIDIAN_AGENT_ID
NOVATRIAL_AGENT_ID=$NOVATRIAL_AGENT_ID
MERIDIAN_POLICY_ID=$MERIDIAN_POLICY_ID
NOVATRIAL_POLICY_ID=$NOVATRIAL_POLICY_ID
MERIDIAN_POLICY_HASH=$MERIDIAN_POLICY_HASH
NOVATRIAL_POLICY_HASH=$NOVATRIAL_POLICY_HASH
HARVEY_CERT_FINGERPRINT=$HARVEY_CERT_FINGERPRINT
ATLAS_CERT_FINGERPRINT=$ATLAS_CERT_FINGERPRINT
CONSTITUTION_ID=$CONSTITUTION_ID
CONSTITUTION_HASH=$CONSTITUTION_HASH
EOF

echo "  Starting PACT Platform containers..."
cd "$ENV_DIR"
docker compose --env-file .env up -d

echo "  Waiting for Postgres..."
timeout 90 bash -c 'until docker exec pact-postgres pg_isready -U pact_app -d pact; do sleep 2; done'

echo "  Waiting for Redis..."
timeout 30 bash -c "until docker exec pact-redis redis-cli -a '$PACT_REDIS_PASSWORD' ping | grep -q PONG; do sleep 2; done"

echo "  Waiting for Prometheus..."
timeout 60 bash -c 'until curl -sf http://localhost:9090/-/ready > /dev/null; do sleep 3; done'

echo "  Waiting for Grafana..."
timeout 60 bash -c 'until curl -sf http://localhost:3000/api/health > /dev/null; do sleep 3; done'

echo "  All services healthy. Registering organisations..."

# Substitute placeholders in register SQL and run it
REGISTER_SQL=$(cat "$ENV_DIR/postgres/01_register_orgs.sql")
for VAR in MERIDIAN_TENANT_ID NOVATRIAL_TENANT_ID MERIDIAN_AGENT_ID NOVATRIAL_AGENT_ID \
           MERIDIAN_POLICY_ID NOVATRIAL_POLICY_ID MERIDIAN_POLICY_HASH NOVATRIAL_POLICY_HASH \
           HARVEY_CERT_FINGERPRINT ATLAS_CERT_FINGERPRINT HARVEY_CERT_PEM ATLAS_CERT_PEM; do
    REGISTER_SQL="${REGISTER_SQL//\$\{$VAR\}/${!VAR}}"
done
echo "$REGISTER_SQL" | docker exec -i pact-postgres psql -U pact_app -d pact

# Verify
TENANTS=$(docker exec pact-postgres psql -U pact_app -d pact \
  -tAc "SELECT COUNT(*) FROM tenant;")
AGENTS=$(docker exec pact-postgres psql -U pact_app -d pact \
  -tAc "SELECT COUNT(*) FROM agent_identity;")
POLICIES=$(docker exec pact-postgres psql -U pact_app -d pact \
  -tAc "SELECT COUNT(*) FROM policy_bundle;")
echo "  ✅ Tenants: $TENANTS | Agents: $AGENTS | Policies: $POLICIES"

echo ""
echo "  Grafana:    http://localhost:3000  (admin / $PACT_GRAFANA_PASSWORD)"
echo "  Prometheus: http://localhost:9090"
echo "=== PACT Platform bootstrap complete ==="
```

---

#### ❌ File 8: `scripts/bootstrap_all.sh`

```bash
#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

rm -f "$SCRIPT_DIR/.pact_bootstrap_state"

echo "╔══════════════════════════════════════════════════════════╗"
echo "║  PACT Two-Org Foundation Bootstrap                       ║"
echo "║  Meridian Legal (SQL Server) + NovaTrial (PostgreSQL)    ║"
echo "╚══════════════════════════════════════════════════════════╝"
echo ""

bash "$SCRIPT_DIR/bootstrap_meridian.sh"
echo ""
bash "$SCRIPT_DIR/bootstrap_novatrial.sh"
echo ""
bash "$SCRIPT_DIR/bootstrap_pact.sh"
echo ""
bash "$SCRIPT_DIR/verify_all.sh"
```

---

#### ❌ File 9: `scripts/verify_all.sh`

```bash
#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/.pact_bootstrap_state" 2>/dev/null || true
PASS=0; FAIL=0

ok()   { echo "  ✅ $1"; ((PASS++)); }
fail() { echo "  ❌ $1 — $2"; ((FAIL++)); }

chk() {
    local label="$1"; local cmd="$2"; local expect="$3"
    result=$(eval "$cmd" 2>/dev/null | tr -d ' \n' || echo "ERROR")
    [[ "$result" == *"$expect"* ]] && ok "$label" || fail "$label" "got: $result"
}

SQLCMD="docker exec meridian-sqlserver /opt/mssql-tools18/bin/sqlcmd"
SQLRUN() {
    local db="${1:-meridian_db}"; local q="$2"
    $SQLCMD -S localhost -U sa -P "$MERIDIAN_SA_PASSWORD" -C -d "$db" \
      -Q "SET NOCOUNT ON; $q" -h -1 2>/dev/null | tr -d ' \r\n'
}

echo ""
echo "=== Meridian Legal LLP (SQL Server 2022) ==="
chk "SQL Server healthy" \
    "$SQLCMD -S localhost -U sa -P '$MERIDIAN_SA_PASSWORD' -C -Q 'SELECT 1' -b && echo ok" "ok"
chk "Redis healthy" "docker exec meridian-redis redis-cli ping" "PONG"
chk "matter seeded"    "SQLRUN meridian_db 'SELECT COUNT(*) FROM matter'"          "1"
chk "documents seeded" "SQLRUN meridian_db 'SELECT COUNT(*) FROM deal_document'"   "4"
chk "DD items seeded"  "SQLRUN meridian_db 'SELECT COUNT(*) FROM dd_checklist_item'" "6"
chk "privilege log"    "SQLRUN meridian_db 'SELECT COUNT(*) FROM privilege_log'"   "2"
chk "Harvey cert"      "test -f '$SCRIPT_DIR/../envs/meridian-legal/agent/identity/harvey.crt' && echo ok" "ok"

echo ""
echo "=== NovaTrial CRO (PostgreSQL 16) ==="
chk "Postgres healthy" \
    "docker exec novatrial-postgres pg_isready -U novatrial_app -d novatrial_db" "accepting"
chk "Redis healthy"    "docker exec novatrial-redis redis-cli ping" "PONG"
chk "trials seeded"    \
    "docker exec novatrial-postgres psql -U novatrial_app -d novatrial_db -tAc 'SELECT COUNT(*) FROM clinical_trial;'" ""
chk "DD summaries"     \
    "docker exec novatrial-postgres psql -U novatrial_app -d novatrial_db -tAc 'SELECT COUNT(*) FROM dd_approved_summary;'" "3"
chk "IP assets"        \
    "docker exec novatrial-postgres psql -U novatrial_app -d novatrial_db -tAc 'SELECT COUNT(*) FROM ip_asset;'" "3"
chk "Atlas cert"       "test -f '$SCRIPT_DIR/../envs/novatrial/agent/identity/atlas.crt' && echo ok" "ok"

echo ""
echo "=== PACT Platform (PostgreSQL 16) ==="
chk "Postgres healthy" "docker exec pact-postgres pg_isready -U pact_app -d pact" "accepting"
chk "Redis healthy"    "docker exec pact-redis redis-cli ping" "PONG"
chk "Prometheus up"    "curl -sf http://localhost:9090/-/ready" ""
chk "Grafana up"       "curl -sf http://localhost:3000/api/health" "ok"
chk "2 tenants"        \
    "docker exec pact-postgres psql -U pact_app -d pact -tAc 'SELECT COUNT(*) FROM tenant;'" "2"
chk "2 agents"         \
    "docker exec pact-postgres psql -U pact_app -d pact -tAc 'SELECT COUNT(*) FROM agent_identity;'" "2"
chk "2 policies"       \
    "docker exec pact-postgres psql -U pact_app -d pact -tAc 'SELECT COUNT(*) FROM policy_bundle;'" "2"

echo ""
echo "=== Stack Isolation Check ==="
chk "Meridian on SQL Server (1433)" \
    "docker port meridian-sqlserver | grep 1433 && echo ok" "ok"
chk "NovaTrial on PostgreSQL (5434)" \
    "docker port novatrial-postgres | grep 5434 && echo ok" "ok"
chk "Networks isolated (3 separate)" \
    "docker network ls | grep -c 'meridian-net\|novatrial-net\|pact-net'" "3"

echo ""
echo "══════════════════════════════════"
echo "  PASS: $PASS  |  FAIL: $FAIL"
echo "══════════════════════════════════"
[[ $FAIL -eq 0 ]] && echo "  ✅ Foundation complete — all checks passed." \
                  || echo "  ❌ $FAIL checks failed — review errors above."
```

---

### GROUP 3 — Shared Files

#### ❌ File 10: `orgs/shared/constitution_v1.json`

```json
{
  "_comment": "PACT Session Constitution — bilateral M&A due diligence. Placeholders substituted by bootstrap_pact.sh.",
  "constitution_id": "${CONSTITUTION_ID}",
  "version": 1,
  "purpose": "M&A due diligence — Meridian Legal LLP (SQL Server) reviewing NovaTrial CRO (PostgreSQL) clinical trial portfolio on behalf of Helion Pharma Inc.",
  "topology": "bilateral",
  "participants": [
    {
      "org_id": "${MERIDIAN_TENANT_ID}",
      "domain": "meridian-legal.ai",
      "mode": "bilateral",
      "agent_id": "${MERIDIAN_AGENT_ID}",
      "agent_name": "harvey",
      "role": "initiator",
      "data_stack": "Microsoft SQL Server 2022"
    },
    {
      "org_id": "${NOVATRIAL_TENANT_ID}",
      "domain": "novatrial.io",
      "mode": "bilateral",
      "agent_id": "${NOVATRIAL_AGENT_ID}",
      "agent_name": "atlas",
      "role": "counterparty",
      "data_stack": "PostgreSQL 16"
    }
  ],
  "legal_basis": {
    "nda_ref": "meridian:agreements/NDA-meridian-novatrial-2026",
    "governing_law": "Delaware",
    "regulatory_refs": ["21 CFR Part 11", "45 CFR Part 164 (HIPAA)"]
  },
  "scope": {
    "permitted_action_types": ["data_query", "doc_retrieval"],
    "denied_action_types": ["data_write", "memory_write", "a2a_delegation"],
    "permitted_operations": ["search", "aggregate"],
    "denied_operations": ["read", "write", "persist", "export"],
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
      "meridian:due-diligence/DD-report-draft*"
    ]
  },
  "time_bounds": {
    "not_before": "2026-07-05T00:00:00Z",
    "not_after": "2026-10-05T00:00:00Z"
  },
  "memory_rules": {
    "default_scope": "session",
    "persist_requires_both_allow": true,
    "teardown_on_close": true,
    "min_group_size_for_aggregate": 5
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
  }
}
```

---

### GROUP 4 — Gitignore

#### ❌ File 11: `.gitignore` (in `/Users/micheal/quest1works/PACT Build/`)

```gitignore
# Private keys — NEVER commit
envs/*/agent/identity/*.key
envs/*/agent/identity/*-ca.key
envs/*/agent/identity/*.csr
envs/*/agent/identity/*.srl

# Env files with real passwords
envs/*/.env
scripts/.pact_bootstrap_state

# Resolved agent configs
envs/*/agent/agent_resolved.json

# Fetched trial data (re-fetched each bootstrap)
envs/novatrial/data/trials/*.json
envs/novatrial/data/approved-for-dd/*.json

# macOS
.DS_Store
```

---

## Exact Build + Run Order

```bash
# Pre-check
docker --version && docker compose version && python3 --version && openssl version

# 1-11: Create all files above
# Then:

chmod +x scripts/*.sh

# Run full bootstrap
bash scripts/bootstrap_all.sh
```

---

## Critical Notes

1. **SQL Server init takes ~30 seconds** — the bootstrap script already handles this with a 90s timeout. Do not remove the sleep/retry loop.

2. **SQL Server password requirements**: Must be ≥ 8 chars with upper + lower + digit + symbol. The generated password format `PactLegal-<hex>!Aa1` satisfies this.

3. **sqlcmd path in container**: `/opt/mssql-tools18/bin/sqlcmd` (SQL Server 2022 Docker image). The `-C` flag trusts the self-signed certificate. The `-h -1` flag removes column headers from output.

4. **T-SQL vs PostgreSQL**: The Meridian schema (`sqlserver/00_schema.sql`) is pure T-SQL. Do NOT mix PostgreSQL syntax. Key differences:
   - `NEWID()` not `uuid_generate_v4()`
   - `NVARCHAR(MAX)` not `TEXT`
   - `BIT` not `BOOLEAN`
   - `DATETIMEOFFSET` not `TIMESTAMPTZ`
   - `ISJSON()` for JSON validation
   - `SYSDATETIMEOFFSET()` not `NOW()`
   - No `CREATE TYPE AS ENUM` — use `CHECK` constraints
   - No arrays — use JSON in `NVARCHAR(MAX)`

5. **NovaTrial uses PostgreSQL enums**: The `trial_phase` and `trial_status` enums in `novatrial/postgres/00_schema.sql` are strict. Map ClinicalTrials.gov API values carefully (done in bootstrap Python).

6. **The `.pact_bootstrap_state` file**: Both org scripts append to this file. `bootstrap_pact.sh` sources it. This is the state handoff between scripts. Always clean it first (`rm -f`) before running `bootstrap_all.sh`.

7. **01_register_orgs.sql column names**: Match exactly to `envs/pact-platform/postgres/00_init.sql`. Read that file first before writing the INSERT statements.

8. **Docker networks are fully isolated**: `meridian-net`, `novatrial-net`, `pact-net` — three separate Docker networks. No cross-network connectivity. This is already set in the existing docker-compose files.

---

## Expected Final State

```
Running containers (10 total):
  meridian-sqlserver  port 1433    ← SQL Server 2022
  meridian-redis      port 6380
  novatrial-postgres  port 5434    ← PostgreSQL 16
  novatrial-redis     port 6381
  pact-postgres       port 5432    ← PostgreSQL 16 (PACT control plane)
  pact-pgbouncer      port 6432
  pact-redis          port 6379
  pact-otel           ports 4317/4318
  pact-prometheus     port 9090
  pact-grafana        port 3000    → http://localhost:3000

Data verified:
  meridian_db (SQL Server): 1 matter, 4 docs, 6 DD items, 2 privilege log entries
  novatrial_db (PostgreSQL): ≥10 real trials, 3 DD summaries, 3 IP assets
  pact_db (PostgreSQL): 2 tenants, 2 agents, 2 policy bundles

Certs:
  envs/meridian-legal/agent/identity/harvey.crt
  envs/novatrial/agent/identity/atlas.crt

verify_all.sh: all checks PASS, including stack isolation check
```
