#!/bin/bash
# generate-snapshot.sh — Generate portable brain snapshot for embedding in projects

set -e

BRAIN_ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
OUTPUT_DIR="${1:-.}"
PROJECT_TYPE="${2:-service-desk}"
CUSTOMER="${3:-strategix}"

echo "🧠 Generating Obsidian Brain snapshot..."
echo "  Brain root: $BRAIN_ROOT"
echo "  Output: $OUTPUT_DIR/brain-snapshot"
echo "  Project type: $PROJECT_TYPE"
echo "  Customer: $CUSTOMER"

# Create snapshot directory structure
SNAPSHOT_DIR="$OUTPUT_DIR/brain-snapshot"
mkdir -p "$SNAPSHOT_DIR"/{lessons,cache,templates}

echo "📋 Copying lessons..."
# Copy universal lessons
cp -v "$BRAIN_ROOT/lessons/universal-patterns.md" "$SNAPSHOT_DIR/lessons/" 2>/dev/null || echo "  (universal-patterns.md not found)"

# Copy customer-specific lessons
if [ -d "$BRAIN_ROOT/lessons/by-customer/$CUSTOMER" ]; then
  cp -v "$BRAIN_ROOT/lessons/by-customer/$CUSTOMER"/*.md "$SNAPSHOT_DIR/lessons/" 2>/dev/null || echo "  (no customer lessons)"
fi

# Copy recent meta-patterns
find "$BRAIN_ROOT/lessons" -maxdepth 1 -name "*.md" -exec cp -v {} "$SNAPSHOT_DIR/lessons/" \; 2>/dev/null || true

echo "💾 Copying cache entries..."
# Copy all cache responses
cp -v "$BRAIN_ROOT/cache/query-responses"/*.md "$SNAPSHOT_DIR/cache/" 2>/dev/null || echo "  (cache empty)"

echo "📐 Copying templates..."
# Copy relevant project-type template
if [ -f "$BRAIN_ROOT/bootstrap/project-types/${PROJECT_TYPE}-template.md" ]; then
  cp -v "$BRAIN_ROOT/bootstrap/project-types/${PROJECT_TYPE}-template.md" "$SNAPSHOT_DIR/templates/"
fi

# Copy anti-patterns
cp -v "$BRAIN_ROOT/bootstrap/anti-patterns.md" "$SNAPSHOT_DIR/templates/" 2>/dev/null || true

# Copy vault structure
cp -v "$BRAIN_ROOT/bootstrap/vault-structure/minimum-vault.md" "$SNAPSHOT_DIR/templates/" 2>/dev/null || true

echo "📝 Generating SNAPSHOT-MANIFEST.json..."
cat > "$SNAPSHOT_DIR/SNAPSHOT-MANIFEST.json" << EOF
{
  "version": "1.0",
  "generated_at": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "project_type": "$PROJECT_TYPE",
  "customer": "$CUSTOMER",
  "source_brain": "$BRAIN_ROOT",
  "contents": {
    "lessons": $(find "$SNAPSHOT_DIR/lessons" -type f -name "*.md" | wc -l),
    "cache_entries": $(find "$SNAPSHOT_DIR/cache" -type f -name "*.md" | wc -l),
    "templates": $(find "$SNAPSHOT_DIR/templates" -type f -name "*.md" | wc -l)
  },
  "manifest_version": "1",
  "offline_capable": true,
  "optional_api_url": "https://brain.strategix.internal/api/query"
}
EOF

echo "📦 Calculating snapshot size..."
SNAPSHOT_SIZE=$(du -sh "$SNAPSHOT_DIR" | cut -f1)
echo "  Snapshot size: $SNAPSHOT_SIZE"

echo ""
echo "✅ Snapshot generated: $SNAPSHOT_DIR"
echo ""
echo "Include in your project:"
echo "  cp -r $SNAPSHOT_DIR /path/to/project/.parent-automation/"
echo ""
echo "Or import into bootstrap:"
echo "  new-project-bootstrap will auto-discover snapshot at .parent-automation/brain-snapshot/"
