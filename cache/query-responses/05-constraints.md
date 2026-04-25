---
query: "What are the critical runtime constraints for a [project-type]?"
optimized_prompt: |
  Identify critical runtime constraints for a [project-type] project.
  
  Constraints are HARD LIMITS — not aspirations, not ideals. They define what IS possible.
  
  For ALL project-types (universal):
  1. Runtime substrate (Cloudflare Workers, Pages, or traditional server?)
  2. Database (D1 SQLite, PostgreSQL, etc.)
  3. Wall-clock limits per request (Workers ~30s, traditional ~60s)
  4. Auth mechanism (Cloudflare Access, OAuth, basic, etc.)
  5. Tenancy model (single-tenant, multi-tenant from day one?)
  6. Currency handling (single currency vs multi-currency?)
  
  For [project-type] specifically:
  - service-desk: Workers + D1, multi-tenant from day zero, ZAR+USD, 30s wall-clock
  - revops: Pages (SPA) + Workers (API), D1, single-tenant, single currency (ZAR only)
  - ops-intelligence: Next.js on Workers, D1, single-tenant, 30s wall-clock, separate cron-worker
  
  Output format:
  ```
  - **[Constraint name]:** Hard limit + implication
  - **[Constraint 2]:** ...
  ```
tier_recommendation: Haiku
cost_estimate: "~900 tokens"
last_updated: "2026-04-25"
cache_hit_rate: "7+ times (every project planning needs to know constraints)"
depends_on: ["bootstrap/project-types"]
---

## Cached Example: Service Desk Constraints

```
- **Runtime:** Cloudflare Workers via Hono + Vite. Wall-clock limit ~30s.
  ⟹ Long-running operations (email ingestion, timesheet aggregation) must be async via Queues
- **Database:** D1 (SQLite) with Drizzle ORM. One D1 database, tenant-scoped.
  ⟹ No cross-tenant queries; 100 bound parameters per query limit
- **Auth:** better-auth with session cookie; CSRF on state-changing routes.
  ⟹ No SSO in Phase 1; credentials (password) + email link only
- **Tenancy:** Multi-tenant from day zero. Middleware-enforced scoping.
  ⟹ Every table has tenant_id; every query filters by tenant; no tenant_id from body (use session)
- **Currency:** ZAR primary, USD secondary. Suffixed columns (_zar, _usd).
  ⟹ No storing money without currency suffix; no implicit ZAR assumption
- **Frontend:** React 19 + Vite + Tailwind v4 + shadcn/ui.
  ⟹ No jQuery, no server-side template rendering; SPA architecture only
- **Event surface:** Cloudflare Queues for internal event bus.
  ⟹ Async processing available; no real-time guarantees (batch processing)
```

## Cached Example: RevOps Constraints

```
- **Auth:** Cloudflare Access (Azure AD SSO). JWT validation via `jose`.
  ⟹ No password auth in app; SSO is mandatory (vs optional in other projects)
  ⟹ No user sign-up flow; user roster comes from Azure AD
- **Edge-only:** Cloudflare Pages (React SPA) + Workers Functions (Hono).
  ⟹ No origin server; all code runs on edge
  ⟹ Workers functions are stateless; state in D1 or KV only
- **[Currency] throughout:** `_[currency]` suffix on all financial columns.
  ⟹ Single currency by design (e.g., ZAR only); no currency conversion
  ⟹ If multi-currency needed in future, major schema rework required
- **D1 limits:** 100 bound parameters per query; no native BOOLEAN/DATETIME.
  ⟹ Use INTEGER (0/1) for booleans; TEXT for dates; parse in application
```

## Cached Example: Ops Intelligence Constraints

```
- **Runtime:** Next.js 16 on Cloudflare Workers via `@opennextjs/cloudflare`.
  ⟹ 30s wall-clock limit; keep retry budgets ≤ 5s per attempt
- **HaloPSA host header:** `servicedesk.strategix.co.za` is CF-proxied.
  ⟹ Requests must target `HALO_API_URL` with `Host` header set to tenant URL
- **Auth:** Hybrid Auth.js (Credentials + bcrypt) with D1 sessions + Cloudflare Access SSO.
  ⟹ D1 stores session tokens; bcrypt hashes passwords; JWT verification via `jose`
- **D1 migrations:** Applied manually via `npx wrangler d1 migrations apply [db-name] --remote`.
  ⟹ CI token scope incomplete; manual apply required for production
- **Cron worker:** Separate deployment in `cron-worker/`.
  ⟹ Deploy: `cd cron-worker && npx wrangler deploy`
  ⟹ Handles longer outages (HaloPSA sync, advisory analysis, rule tuning)
```

## Why Constraints Matter

Constraints are not obstacles — they're reality. Ignoring them causes:
- **wall-clock limit**: 30s timeout if operation takes 45s
- **100 bound params**: Query fails silently if 101+ parameters
- **Multi-tenant enforcement**: SQL injection when tenant_id forgotten
- **D1 BOOLEAN**: Integer 0/1 stored as TEXT; confusing queries
- **Currency suffix**: Financial calculations wrong when currency implicit

Each constraint is learned from failure (usually in earlier project).

## Common Mistakes

- ❌ **Writing as aspirations, not constraints**: "We'll optimize for 10s response time" (aspiration, not constraint)
- ❌ **Missing implications**: Stating constraint without saying why it matters
- ❌ **Soft constraints presented as hard**: "We prefer Edge but could use origin server" (not a constraint if optional)
- ❌ **Not enforcing at build time**: Constraint known, but no lint/check to prevent violation

## When to Use This Cache
- Bootstrap step 2 (identify constraints before designing)
- Architecture decision (does this approach work within constraints?)
- Code review (spot: this query has 150 parameters, violates 100-param constraint)
- Performance review (are we respecting wall-clock limits?)
