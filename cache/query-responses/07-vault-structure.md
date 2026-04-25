---
query: "What vault structure should a [project-type] have?"
optimized_prompt: |
  Design vault (documentation) structure for a [project-type] project.
  
  Vault is a secondary source of truth for docs that don't belong in-repo:
  - Business context (customer workflows, domain concepts)
  - Design decisions (why we chose this architecture, alternatives considered)
  - Operational runbooks (how to handle incidents, deploy, scale)
  - Training materials (how new team members learn the system)
  - Historical context (why we built this, what was the original problem?)
  
  For [project-type], typical vault structure:
  ```
  ~/vaults/[project-name]-docs/
  ├── README.md                         ← Entry point
  ├── 00-Quick-Start.md                 ← 5-minute orientation
  ├── Architecture/
  │   ├── System-Design.md
  │   ├── Data-Model.md
  │   ├── Integration-Points.md
  │   └── Multi-[Tenant|Currency]-Approach.md
  ├── Operations/
  │   ├── Deployment.md                 ← CI/CD, rollback procedures
  │   ├── Monitoring.md                 ← Alerting, dashboards
  │   ├── Incident-Response.md          ← What to do if X breaks
  │   └── Runbooks/
  │       ├── Scale-Database.md
  │       ├── Recover-from-Crash.md
  │       └── Rotate-Secrets.md
  ├── Domain/
  │   ├── [Domain-Concepts].md
  │   ├── [Workflow-Guides].md
  │   └── [Business-Rules].md
  ├── Development/
  │   ├── Onboarding.md                 ← How to get started locally
  │   ├── Testing-Strategy.md
  │   ├── Common-Patterns.md
  │   └── Troubleshooting.md
  └── Decisions/
      └── [ADR-NNNN-Decision-Title.md]
  ```
  
  For service-desk: include timesheet audit, multi-tenant security model, ticket SLA logic
  For revops: include rate card management, margin approval workflow, commission calculation
  For ops-intelligence: include connector architecture, advisory analysis logic, rule tuning
tier_recommendation: Haiku
cost_estimate: "~1100 tokens"
last_updated: "2026-04-25"
cache_hit_rate: "4+ times (when vault structure initialized)"
depends_on: ["bootstrap/project-types"]
---

## Cached Example: Service Desk Vault

```
strategix-servicedesk-docs/
├── README.md
├── 00-Quick-Start.md
├── Architecture/
│   ├── System-Design.md (multi-tenant enforcement at every layer)
│   ├── Data-Model.md (tickets, time_entries, timesheets)
│   ├── Time-Capture-Engine.md (timer, manual, activity dwell)
│   └── Timesheet-Approval.md (customer sign-off, billing accuracy)
├── Operations/
│   ├── Deployment.md (Workers deploy, D1 migration apply)
│   ├── Monitoring.md (error rates, timesheet accuracy metrics)
│   └── Incident-Response.md (if worker crashes, if D1 unavailable)
├── Domain/
│   ├── ITIL-Incident-Model.md
│   ├── Timesheet-Rules.md (rounding, approval gates)
│   └── Multi-Tenant-Isolation.md (security model, audit requirements)
├── Development/
│   ├── Onboarding.md
│   ├── Testing-Strategy.md (unit, integration, E2E)
│   └── Common-Patterns.md (time entry validation, timesheet aggregate)
└── Decisions/
    ├── ADR-001-Observed-Time-Capture.md
    ├── ADR-002-D1-Multi-Tenant.md
    └── ADR-003-Soft-Delete-Strategy.md
```

## Cached Example: RevOps Vault

```
strategix-revops-docs/
├── README.md
├── 00-Quick-Start.md
├── Architecture/
│   ├── System-Design.md (Pages SPA + Workers API)
│   ├── Rate-Card-Engine.md
│   ├── Margin-Approval-Workflow.md
│   └── Commission-Calculation.md
├── Operations/
│   ├── Deployment.md (Pages deploy, Workers deploy, D1 schema)
│   ├── Monitoring.md (quote creation rate, margin approval SLA)
│   └── Runbooks/
│       ├── Update-Rate-Card.md
│       └── Manual-Commission-Reconciliation.md
├── Domain/
│   ├── Commercial-Concepts.md (quote, discount, margin, commission)
│   ├── Pricing-Rules.md
│   └── Financial-Controls.md (who can approve what cost?)
├── Development/
│   ├── Onboarding.md
│   └── Testing-Strategy.md
└── Decisions/
    ├── ADR-001-Single-Currency.md
    └── ADR-002-Field-Level-Shaping.md
```

## Cached Example: Ops Intelligence Vault

```
strategix-ioc-docs/
├── README.md
├── 00-Quick-Start.md
├── Architecture/
│   ├── System-Design.md (signal ingestion, correlation, advisory)
│   ├── Connector-Architecture.md (how to add new sources)
│   ├── Signal-Correlation-Engine.md
│   └── Advisory-Analysis.md (Claude batch runs, nightly)
├── Operations/
│   ├── Deployment.md (main Worker + cron-worker deploy)
│   ├── Monitoring.md (signal latency, advisory accuracy metrics)
│   ├── Cron-Worker-Ops.md (HaloPSA sync schedule, N-central polling)
│   └── Runbooks/
│       ├── Manual-Rule-Tuning.md
│       └── Recover-from-Connector-Outage.md
├── Domain/
│   ├── ITSM-Concepts.md (SLA, priority, escalation)
│   ├── Connector-Onboarding.md
│   └── Advisory-Governance.md (when to trust an advisory)
├── Development/
│   ├── Onboarding.md
│   ├── Testing-Strategy.md (unit, connector mocking, integration)
│   └── Connector-Pattern.md (template for new source)
└── Decisions/
    ├── ADR-001-Advisory-Batch-Not-Realtime.md
    └── ADR-002-Separate-Cron-Deployment.md
```

## What Does NOT Go in Vault

- ❌ **Code that should be in repo**: Use repo source, not vault docs
- ❌ **Live state that drifts**: Use `.planning/STATE.md` in repo for current status
- ❌ **Credentials or secrets**: Vault should reference secret management, not store them
- ❌ **Every commit message**: Vault captures *why* architecturally; commits capture *what* technically

## When to Use This Cache
- Bootstrap step 8 (create vault structure)
- Onboarding (new team member: "start at vault README")
- Decision log (every architectural decision gets an ADR in vault)

## Related Vault Locations
- **Strategix global vault**: `~/vaults/StrategixMSPDocs/` (programme doctrine, not project-specific)
- **Project vault**: `~/vaults/[project-name]-docs/` (project-specific domain knowledge)
