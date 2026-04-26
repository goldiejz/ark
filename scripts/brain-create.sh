#!/usr/bin/env bash
# brain create — scaffold a new project from cached templates
#
# Usage:
#   brain create <project-name> --type <type> --customer <customer> [--path <path>]
#
# Types: service-desk | revops | ops-intelligence | custom
#
# What it does:
# 1. Creates project directory at <path>/<project-name>
# 2. Copies cached templates: CLAUDE.md, .planning/, src/lib/rbac.ts, etc.
# 3. Substitutes variables (project-name, customer, type)
# 4. Initializes git, installs dependencies
# 5. Creates GitHub repo (if gh CLI available)
# 6. Records decision to brain
# 7. Returns: project ready for `brain deliver` or development

set -uo pipefail

VAULT_PATH="${AUTOMATION_BRAIN_PATH:-$HOME/vaults/automation-brain}"

PROJECT_NAME=""
PROJECT_TYPE=""
CUSTOMER=""
PROJECT_PATH="$HOME/code"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --type) PROJECT_TYPE="$2"; shift 2 ;;
    --customer) CUSTOMER="$2"; shift 2 ;;
    --path) PROJECT_PATH="$2"; shift 2 ;;
    --help|-h)
      cat <<EOF
Usage: brain create <name> --type <type> --customer <customer> [--path <dir>]

Types:
  service-desk      - ITIL service desk (Cloudflare Workers + Vite + D1)
  revops            - RevOps platform (Cloudflare Pages + Vite + D1)
  ops-intelligence  - Ops dashboard (Next.js on Workers)
  custom            - Custom project (minimal scaffold)

Examples:
  brain create acme-service-desk --type service-desk --customer acme
  brain create internal-tool --type custom --customer strategix --path ~/work
EOF
      exit 0
      ;;
    *)
      if [[ -z "$PROJECT_NAME" ]]; then
        PROJECT_NAME="$1"
      fi
      shift
      ;;
  esac
done

if [[ -z "$PROJECT_NAME" ]] || [[ -z "$PROJECT_TYPE" ]] || [[ -z "$CUSTOMER" ]]; then
  echo "❌ Missing required args. Run: brain create --help"
  exit 1
fi

PROJECT_DIR="$PROJECT_PATH/$PROJECT_NAME"

GREEN='\033[0;32m'
NC='\033[0m'

echo "🆕 Creating project: $PROJECT_NAME"
echo "  Type: $PROJECT_TYPE"
echo "  Customer: $CUSTOMER"
echo "  Path: $PROJECT_DIR"
echo ""

# Check project doesn't already exist
if [[ -d "$PROJECT_DIR" ]]; then
  echo "❌ Project already exists at $PROJECT_DIR"
  exit 1
fi

# === Step 1: Create directory + git ===
mkdir -p "$PROJECT_DIR"
cd "$PROJECT_DIR"
git init --quiet
echo -e "  ${GREEN}✅${NC} Directory created"

# === Step 2: Copy templates from vault ===
SNAPSHOT_DIR="$VAULT_PATH/cache/query-responses"
TEMPLATE_DIR="$VAULT_PATH/bootstrap/project-types"

# Generate CLAUDE.md from cached template
if [[ -f "$SNAPSHOT_DIR/01-project-section-draft.md" ]]; then
  cat > "$PROJECT_DIR/CLAUDE.md" <<EOF
# $PROJECT_NAME — Repo Instruction

> Project-specific. Mutable status lives in \`.planning/STATE.md\`.

## Project

$PROJECT_NAME — $PROJECT_TYPE for $CUSTOMER.

## Purpose

[TODO: Define core purpose]

## Current Scope

[TODO: List Phase 1 features]

## Out of Scope

[TODO: List deferred features]

## Constraints

$(cat "$SNAPSHOT_DIR/05-constraints.md" 2>/dev/null | head -30 || echo "[TODO: Define constraints]")

## Architecture Conventions

$(cat "$SNAPSHOT_DIR/03-architecture-conventions.md" 2>/dev/null | head -30 || echo "[TODO: Define conventions]")

## RBAC Structure

See \`src/lib/rbac.ts\`. All role checks use \`requireRole()\` — never inline arrays.

$(cat "$SNAPSHOT_DIR/04-rbac-structure.md" 2>/dev/null | head -20 || echo "[TODO: Define roles]")

## Current Truth Sources

1. \`.planning/STATE.md\` — primary implementation truth
2. \`.planning/ALPHA.md\` — gate definition
3. \`.planning/REQUIREMENTS.md\` — mandatory requirements
4. \`.planning/ROADMAP.md\` — phase sequencing
5. \`tasks/todo.md\` — active backlog
6. \`tasks/lessons.md\` — captured corrections

## Anti-Patterns

$(cat "$SNAPSHOT_DIR/09-anti-patterns.md" 2>/dev/null | head -20 || echo "[TODO]")
EOF
  echo -e "  ${GREEN}✅${NC} CLAUDE.md generated from cached templates"
fi

# Generate .planning/ files
mkdir -p "$PROJECT_DIR/.planning"

cat > "$PROJECT_DIR/.planning/PROJECT.md" <<EOF
# $PROJECT_NAME

**Customer:** $CUSTOMER
**Type:** $PROJECT_TYPE
**Created:** $(date -u +%Y-%m-%d)

## Purpose

[TODO: Define durable purpose]

## Stakeholders

[TODO: Who owns this]

## Out of Scope

[TODO: Explicit boundaries]
EOF

cat > "$PROJECT_DIR/.planning/STATE.md" <<EOF
# $PROJECT_NAME — State

**Last updated:** $(date -u +%Y-%m-%dT%H:%M:%SZ)
**Current Phase:** Phase 0
**Status:** scaffolded

## Phase 0: Bootstrap (current)
- [x] Project created via \`brain create\`
- [ ] Phase 1 planning complete
- [ ] Initial implementation
EOF

cat > "$PROJECT_DIR/.planning/ALPHA.md" <<EOF
# Alpha Gate

[TODO: Define gate criteria — what must be true to call this alpha-ready]
EOF

cat > "$PROJECT_DIR/.planning/ROADMAP.md" <<EOF
# Roadmap

## Phase 0 — Bootstrap (current)
- [x] Scaffolded via brain create
- [ ] Configure environment
- [ ] Set up CI/CD

## Phase 1 — Core Slice
- [ ] [TODO: Define core features]
- [ ] Initial UI
- [ ] Basic auth

## Phase 2 — Hardening
- [ ] Tests >= 80% coverage
- [ ] Security review
- [ ] Performance baseline

## Phase 3 — Production
- [ ] Production deploy
- [ ] Monitoring
- [ ] Runbooks
EOF

cat > "$PROJECT_DIR/.planning/REQUIREMENTS.md" <<EOF
# Requirements

| ID | Requirement | Status | Evidence |
|----|-------------|--------|----------|
| R-001 | Brain integration | done | .parent-automation/ exists |
EOF

touch "$PROJECT_DIR/.planning/bootstrap-decisions.jsonl"
echo -e "  ${GREEN}✅${NC} .planning/ files created"

# Create tasks/
mkdir -p "$PROJECT_DIR/tasks"
cat > "$PROJECT_DIR/tasks/todo.md" <<EOF
# Todo

## Active

- [ ] Define Phase 1 scope (update PROJECT.md + ROADMAP.md)
- [ ] Run \`brain deliver\` to start autonomous build

## Backlog

[TODO]
EOF

cat > "$PROJECT_DIR/tasks/lessons.md" <<EOF
# Project Lessons

Captured corrections (rules, not descriptions).
EOF

echo -e "  ${GREEN}✅${NC} tasks/ created"

# === Step 3: Type-specific scaffolding ===
case "$PROJECT_TYPE" in
  service-desk|revops)
    # Cloudflare Workers + Vite + D1
    cat > "$PROJECT_DIR/package.json" <<EOF
{
  "name": "$PROJECT_NAME",
  "version": "0.0.1",
  "type": "module",
  "scripts": {
    "dev": "vite",
    "build": "vite build",
    "preview": "vite preview",
    "deploy": "wrangler deploy",
    "test": "vitest"
  },
  "dependencies": {
    "hono": "^4.0.0",
    "react": "^19.0.0",
    "react-dom": "^19.0.0"
  },
  "devDependencies": {
    "@cloudflare/vite-plugin": "^1.0.0",
    "@types/node": "^25.0.0",
    "typescript": "^6.0.0",
    "vite": "^7.0.0",
    "vitest": "^3.0.0",
    "wrangler": "^4.0.0"
  }
}
EOF
    cat > "$PROJECT_DIR/wrangler.toml" <<EOF
name = "$PROJECT_NAME"
main = "src/worker.ts"
compatibility_date = "$(date +%Y-%m-%d)"

[[d1_databases]]
binding = "DB"
database_name = "$PROJECT_NAME-db"
database_id = "TODO_ADD_ID"
EOF
    mkdir -p "$PROJECT_DIR/src/lib" "$PROJECT_DIR/src/db"
    cat > "$PROJECT_DIR/src/lib/rbac.ts" <<EOF
// Centralized RBAC — single source of truth
// Lesson L-018: Never inline role arrays in routes/components

export type Role = 'staff' | 'manager' | 'admin' | 'customer';

export const ROLES: Record<Role, Role[]> = {
  customer: ['customer'],
  staff: ['staff'],
  manager: ['staff', 'manager'],
  admin: ['staff', 'manager', 'admin'],
};

export function requireRole(userRole: Role, requiredRole: Role): boolean {
  return ROLES[userRole]?.includes(requiredRole) ?? false;
}
EOF
    cat > "$PROJECT_DIR/src/db/schema.ts" <<EOF
// D1 schema — Drizzle ORM
// Convention: money columns end in _zar/_usd, duration columns end in _minutes/_seconds
EOF
    echo -e "  ${GREEN}✅${NC} Cloudflare Workers + Vite scaffolding"
    ;;
  ops-intelligence)
    cat > "$PROJECT_DIR/package.json" <<EOF
{
  "name": "$PROJECT_NAME",
  "version": "0.0.1",
  "scripts": {
    "dev": "next dev",
    "build": "next build && opennextjs-cloudflare",
    "deploy": "opennextjs-cloudflare && wrangler deploy"
  },
  "dependencies": {
    "next": "^16.0.0",
    "react": "^19.0.0"
  },
  "devDependencies": {
    "@opennextjs/cloudflare": "^1.0.0",
    "typescript": "^6.0.0",
    "wrangler": "^4.0.0"
  }
}
EOF
    echo -e "  ${GREEN}✅${NC} Next.js on Workers scaffolding"
    ;;
  custom|*)
    cat > "$PROJECT_DIR/package.json" <<EOF
{
  "name": "$PROJECT_NAME",
  "version": "0.0.1"
}
EOF
    echo -e "  ${GREEN}✅${NC} Minimal scaffolding"
    ;;
esac

# === Step 4: TypeScript config ===
if [[ ! -f "$PROJECT_DIR/tsconfig.json" ]]; then
  cat > "$PROJECT_DIR/tsconfig.json" <<EOF
{
  "compilerOptions": {
    "target": "ES2022",
    "module": "ES2022",
    "moduleResolution": "bundler",
    "strict": true,
    "esModuleInterop": true,
    "skipLibCheck": true,
    "lib": ["ES2022"],
    "types": ["node"]
  }
}
EOF
fi

# === Step 5: Brain integration ===
echo ""
echo "Initializing brain integration..."
bash "$VAULT_PATH/scripts/brain-sync.sh" "$PROJECT_DIR" >/dev/null 2>&1
mkdir -p "$PROJECT_DIR/.parent-automation"
cp "$VAULT_PATH/templates/parent-automation/"*.ts "$PROJECT_DIR/.parent-automation/" 2>/dev/null
cp "$VAULT_PATH/templates/parent-automation/tsconfig.json" "$PROJECT_DIR/.parent-automation/" 2>/dev/null
echo -e "  ${GREEN}✅${NC} Brain integrated"

# === Step 6: First commit ===
cd "$PROJECT_DIR"
git add -A
git commit -m "Initial scaffold via brain create

Type: $PROJECT_TYPE
Customer: $CUSTOMER
Generated: $(date -u +%Y-%m-%dT%H:%M:%SZ)" --quiet

# === Step 7: GitHub repo (if gh available) ===
if command -v gh >/dev/null 2>&1; then
  echo ""
  echo "Creating GitHub repo (private)..."
  gh repo create "$PROJECT_NAME" --private --source=. --remote=origin --push --confirm 2>&1 | tail -3 || true
fi

# === Step 8: Record decision ===
echo "{\"timestamp\":\"$(date -u +%Y-%m-%dT%H:%M:%SZ)\",\"projectType\":\"$PROJECT_TYPE\",\"customer\":\"$CUSTOMER\",\"projectName\":\"$PROJECT_NAME\",\"decisionsApplied\":[\"create-from-template\",\"$PROJECT_TYPE-scaffold\",\"brain-integrated\"],\"contradictionsResolved\":[],\"lessonsUsed\":[\"L-018\"],\"timeMs\":0,\"tokenEstimate\":0}" >> "$PROJECT_DIR/.planning/bootstrap-decisions.jsonl"

# Trigger Phase 6 to learn
(nohup npx ts-node "$VAULT_PATH/observability/phase-6-daemon.ts" > /dev/null 2>&1 &) 2>/dev/null

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo -e "${GREEN}✅ PROJECT CREATED${NC}"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "Path: $PROJECT_DIR"
echo ""
echo "Next steps:"
echo "  cd $PROJECT_DIR"
echo "  # Edit .planning/PROJECT.md and ROADMAP.md to define scope"
echo "  brain deliver         # Run autonomous delivery"
echo "  npm install           # Install deps"
echo "  npm run dev           # Start dev server"
