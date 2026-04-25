---
query: "How to structure RBAC for a [project-type]?"
optimized_prompt: |
  Design RBAC structure for a [project-type] project.
  
  Steps:
  1. Identify role archetypes (who uses this system?)
  2. Define permissions per role
  3. Create role constants in centralized file
  4. Wire guards into routes (requireRole() pattern)
  5. Document role matrix (which role sees/does what?)
  
  For [project-type], typical roles:
  - service-desk: ENGINEER, MANAGER, ADMIN, CUSTOMER
  - revops: SALES, MANAGER, FINANCE, ADMIN
  - ops-intelligence: OPERATOR, MANAGER, ADMIN
  
  Output:
  ```typescript
  // src/lib/rbac.ts or src/lib/auth-guards.ts
  export const ROLES = {
    ENGINEER: "engineer",
    MANAGER: "manager",
    ADMIN: "admin",
  } as const;
  
  export const ROLE_PERMISSIONS = {
    engineer: ["view:tickets", "create:time_entry", "view:own_timesheets"],
    manager: ["view:all_tickets", "approve:timesheet", "view:reports"],
    admin: ["*"],
  };
  
  export function requireRole(...roles: string[]) {
    // Guard implementation
  }
  ```
  
  Then in routes:
  ```typescript
  export async function POST(request: Request) {
    await requireRole(ROLES.MANAGER, ROLES.ADMIN);
    // handler logic
  }
  ```
  
  Use bootstrap template for [project-type] as reference for role archetypes.
tier_recommendation: Sonnet
cost_estimate: "~1500 tokens"
last_updated: "2026-04-25"
cache_hit_rate: "6+ times (all projects need RBAC wiring)"
depends_on: ["bootstrap/project-types", "L-018"]
---

## Cached Example: Service Desk RBAC

```typescript
// src/lib/rbac.ts
export const ROLES = {
  ENGINEER: "engineer",
  MANAGER: "manager",
  ADMIN: "admin",
  CUSTOMER: "customer",
} as const;

export const ROLE_PERMISSIONS = {
  engineer: [
    "ticket:view:assigned",
    "ticket:view:own_projects",
    "time:create",
    "time:view:own",
    "timesheet:view:own",
    "timesheet:submit",
  ],
  manager: [
    "ticket:view:all",
    "ticket:create",
    "ticket:update:status",
    "time:view:team",
    "timesheet:view:team",
    "timesheet:approve",
    "report:view",
  ],
  admin: ["*"],
  customer: [
    "ticket:view:own",
    "ticket:create",
    "ticket:comment:view",
    "timesheet:sign:own",
  ],
};

export async function requireRole(...allowedRoles: string[]) {
  // Check session.user.role against allowedRoles
  // Return 403 if not authorized
}
```

### Role Matrix (Service Desk)
| Action | Engineer | Manager | Admin | Customer |
|--------|----------|---------|-------|----------|
| View own tickets | ✅ | ✅ | ✅ | ✅ |
| View team tickets | ❌ | ✅ | ✅ | ❌ |
| Create time entry | ✅ | ❌ | ✅ | ❌ |
| Approve timesheet | ❌ | ✅ | ✅ | ❌ |
| Sign timesheet | ❌ | ✅ | ✅ | ✅ |

## Cached Example: RevOps RBAC

```typescript
// functions/api/middleware/rbac.ts
const ROLES = {
  SALES: "sales",
  MANAGER: "manager",
  FINANCE: "finance",
  ADMIN: "admin",
};

const ROLE_PERMISSIONS = {
  sales: ["quote:create", "quote:view:own", "quote:send"],
  manager: ["quote:approve", "pipeline:view", "commission:view"],
  finance: ["quote:view:cost", "commission:view:full", "report:export"],
  admin: ["*"],
};
```

## Cached Example: Ops Intelligence RBAC

```typescript
// src/lib/auth-guards.ts
const ROLES = {
  OPERATOR: "operator",
  MANAGER: "manager",
  ADMIN: "admin",
};

const ROLE_PERMISSIONS = {
  operator: [
    "event:view",
    "rule:toggle",
    "advisory:ack",
    "advisory:dismiss",
  ],
  manager: [
    "event:view:all",
    "rule:tune_confidence",
    "report:generate",
  ],
  admin: ["*"],
};
```

## Common Anti-Patterns

- ❌ **Inline role arrays**: `if (user.role === "engineer" || user.role === "manager")` — centralize in RBAC file
- ❌ **Over-permissioning**: "Manager should be able to do everything Engineer can" — explicitly enumerate manager permissions, don't assume inheritance
- ❌ **No role matrix**: Can't tell at a glance what each role can do
- ❌ **Permission creep**: Roles gain permissions over time without removing old ones
- ❌ **Forgetting to audit**: Sensitive operations (approve, delete, export) should log who did it
- ❌ **No field-level shaping**: Admin can see cost/margin, but Sales shouldn't — filter at response layer

## Related Lessons
- **L-018: RBAC Enum Completeness** — Every new role must enumerate every existing `requireRole()` call-site
- **L-020: Manager Role Narrowing** — Manager roles should inherit narrowly scoped capabilities, not full STAFF authority

## When to Use This Cache
- Bootstrap step 4 (RBAC design)
- Code review (spot: is this role properly guarded?)
- Onboarding (new role added — update role matrix)
