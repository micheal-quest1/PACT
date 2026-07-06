# PACT — Two-Organisation Foundation

This repository contains the foundational development environment for **PACT**, a cross-organisational AI governance platform. It provides a complete, stack-agnostic sandbox demonstrating how PACT securely governs AI agent interactions between two fully isolated enterprises.

## The Scenario: M&A Due Diligence

This sandbox models a real-world, high-value business tension (the 'Tier 1A - Legal' beachhead):

1. **Meridian Legal LLP (`meridian-legal.ai`)**: An AmLaw 200 M&A law firm representing an acquiring pharma company. Their AI agent (**Harvey**) needs to investigate the target company's clinical trial portfolio. They use a Microsoft enterprise stack (**SQL Server 2022**).
2. **NovaTrial CRO (`novatrial.io`)**: The target Contract Research Organisation. They hold highly sensitive clinical trial results and proprietary methodologies. Their AI agent (**Atlas**) manages this data. They use an open-source stack (**PostgreSQL 16**).

**The Tension:** Meridian's Harvey agent needs to analyze NovaTrial's data to approve a $500M acquisition. However, NovaTrial cannot expose raw patient data or intellectual property.

**The Solution:** PACT sits between them. Harvey queries NovaTrial's data, but PACT intercepts the query, normalises it across the different database stacks, and simultaneously evaluates both organisations' Cedar policies. Only actions explicitly allowed by *both* policies (e.g., viewing aggregate trial summaries) are permitted.

## Architecture: Three Isolated Environments

To prove PACT's zero-trust model, we do not fake isolation. This repository provisions three completely separate environments, with no shared databases, caches, or networks. They communicate only via mTLS to the PACT Gateway.

```
┌────────────────────────┐         ┌────────────────────────┐
│  envs/meridian-legal/  │         │  envs/novatrial/       │
│  ───────────────────── │         │  ──────────────────    │
│  DB: SQL Server 2022   │         │  DB: PostgreSQL 16     │
│  Agent: Harvey         │         │  Agent: Atlas          │
│  Network: meridian-net │         │  Network: novatrial-net│
│  Ports: 1433, 6380     │         │  Ports: 5434, 6381     │
└──────────┬─────────────┘         └──────────┬─────────────┘
           │ mTLS                             │ mTLS
           └────────────┐   ┌─────────────────┘
                        ↓   ↓
           ┌─────────────────────────────────────┐
           │  envs/pact-platform/                │
           │  ────────────────────────────────── │
           │  DB: PostgreSQL 16 (Control Plane)  │
           │  pgBouncer, Redis, OTel, Prometheus │
           │  Network: pact-net                  │
           │  Ports: 5432, 6432, 6379, 50051     │
           └─────────────────────────────────────┘
```

## Heterogeneous Tech Stacks

This sandbox intentionally uses different database technologies:
- **Meridian Legal:** Microsoft SQL Server 2022 (T-SQL)
- **NovaTrial CRO:** PostgreSQL 16 (PL/pgSQL)

This proves PACT is **stack-agnostic**. The MCP Protocol Adapter normalises queries from completely different languages into a universal Tool-Call Context before governance is applied.

## Data & Policies

We do not use mock "foo/bar" data. The environments are seeded with production-realistic structures:
- **Meridian Legal:** Contains M&A deal room documents, a due diligence checklist, and a strictly internal 'privilege log' that their Cedar policy explicitly forbids sharing.
- **NovaTrial CRO:** Seeded dynamically via an API script that pulls **real Phase 2 Oncology clinical trials** directly from ClinicalTrials.gov. Their Cedar policy allows sharing summary views but hard-blocks the raw API responses and IP methodology.

## Getting Started

*(Note: The implementation of these scripts is pending the next phase of development with Devin).*

1. Ensure Docker, Python 3, and OpenSSL are installed.
2. Make scripts executable: `chmod +x scripts/*.sh`
3. Run the bootstrap sequence: `bash scripts/bootstrap_all.sh`

This will generate UUIDs, create X.509 certificates, fetch live clinical data, and spin up all three Docker Compose environments.

## Core Schema Files

If you are looking for the canonical machine-readable contracts generated from the PACT Product Specification, they are included at the root:
- `pact_v1.proto` (Hot-path gRPC contract)
- `pact_openapi.yaml` (REST control-plane surface)
- `pact_schema.sql` (Control-plane database DDL)
