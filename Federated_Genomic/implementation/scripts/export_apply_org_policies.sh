#!/bin/bash
# =============================================================================
# Organization Policy Export, Project Bootstrap & Apply Tool
# =============================================================================
# Purpose: Export org policies from source project, optionally create new 
#          project, and apply policies to target project.
# Usage: 
#   ./export_apply_org_policies.sh --source SOURCE_PROJECT --target TARGET_PROJECT
#   ./export_apply_org_policies.sh --source SOURCE_PROJECT --create-new NEW_PROJECT_ID
# =============================================================================

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info()    { echo -e "${BLUE}[INFO]${NC} $1"; }
log_success() { echo -e "${GREEN}[OK]${NC} $1"; }
log_warn()    { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error()   { echo -e "${RED}[ERROR]${NC} $1"; }

# =============================================================================
# Parse Arguments
# =============================================================================

show_usage() {
    echo "Usage: $0 [OPTIONS]"
    echo ""
    echo "Options:"
    echo "  --source, -s      Source project to export org policies from (required)"
    echo "  --target, -t      Target project to apply policies to"
    echo "  --create-new, -c  Create a new project with this ID and apply policies"
    echo "  --billing, -b     Billing account ID (required if creating new project)"
    echo "  --org, -o         Organization ID (optional, for new project)"
    echo "  --folder, -f      Folder ID (optional, for new project under a folder)"
    echo "  --export-only     Only export policies, don't apply"
    echo "  --help, -h        Show this help"
    echo ""
    echo "Examples:"
    echo "  # Export from old project and apply to existing project"
    echo "  $0 --source lifescience-project-469915 --target my-new-project"
    echo ""
    echo "  # Export, create new project, and apply"
    echo "  $0 --source lifescience-project-469915 --create-new my-new-genomics --billing 01ABCD-EFGH12-345678"
    echo ""
    echo "  # Export only (for review before applying)"
    echo "  $0 --source lifescience-project-469915 --export-only"
    exit 1
}

SOURCE_PROJECT=""
TARGET_PROJECT=""
CREATE_NEW_PROJECT=""
BILLING_ACCOUNT=""
ORG_ID=""
FOLDER_ID=""
EXPORT_ONLY=false

while [[ $# -gt 0 ]]; do
    case $1 in
        --source|-s)      SOURCE_PROJECT="$2"; shift 2 ;;
        --target|-t)      TARGET_PROJECT="$2"; shift 2 ;;
        --create-new|-c)  CREATE_NEW_PROJECT="$2"; shift 2 ;;
        --billing|-b)     BILLING_ACCOUNT="$2"; shift 2 ;;
        --org|-o)         ORG_ID="$2"; shift 2 ;;
        --folder|-f)      FOLDER_ID="$2"; shift 2 ;;
        --export-only)    EXPORT_ONLY=true; shift ;;
        --help|-h)        show_usage ;;
        *)                log_error "Unknown option: $1"; show_usage ;;
    esac
done

# Validate required arguments
if [ -z "$SOURCE_PROJECT" ]; then
    log_error "Source project is required"
    show_usage
fi

if [ -z "$TARGET_PROJECT" ] && [ -z "$CREATE_NEW_PROJECT" ] && [ "$EXPORT_ONLY" = false ]; then
    log_error "Either --target or --create-new is required (unless using --export-only)"
    show_usage
fi

if [ -n "$CREATE_NEW_PROJECT" ] && [ -z "$BILLING_ACCOUNT" ]; then
    log_error "Billing account (--billing) is required when creating a new project"
    show_usage
fi

# Set target project
if [ -n "$CREATE_NEW_PROJECT" ]; then
    TARGET_PROJECT="$CREATE_NEW_PROJECT"
fi

# =============================================================================
# Main Script
# =============================================================================

OUTPUT_DIR="./org_policies_export_${SOURCE_PROJECT}"
mkdir -p "$OUTPUT_DIR"

echo ""
echo "=============================================="
echo "  Organization Policy Tool"
echo "=============================================="
echo "  Source Project:  $SOURCE_PROJECT"
if [ "$EXPORT_ONLY" = true ]; then
    echo "  Mode:            Export only"
else
    echo "  Target Project:  $TARGET_PROJECT"
    echo "  Create New:      ${CREATE_NEW_PROJECT:-No}"
fi
echo "=============================================="
echo ""

# -----------------------------------------------------------------------------
# Step 1: Export org policies from source project
# -----------------------------------------------------------------------------
log_info "Exporting org policies from $SOURCE_PROJECT..."

# List all org policies (using --project flag, no need to switch gcloud config)
gcloud resource-manager org-policies list \
    --project="$SOURCE_PROJECT" \
    --format="value(constraint)" > "$OUTPUT_DIR/policy_list.txt" 2>/dev/null || {
        log_error "Failed to list org policies. Check project access."
        exit 1
    }

POLICY_COUNT=$(wc -l < "$OUTPUT_DIR/policy_list.txt" | tr -d ' ')
log_info "Found $POLICY_COUNT org policies"

# Export each policy
while read -r constraint; do
    if [ -n "$constraint" ]; then
        policy_name=$(echo "$constraint" | sed 's|/|_|g')
        
        gcloud resource-manager org-policies describe "$constraint" \
            --project="$SOURCE_PROJECT" \
            --format=json > "$OUTPUT_DIR/${policy_name}.json" 2>/dev/null || true
    fi
done < "$OUTPUT_DIR/policy_list.txt"

log_success "Policies exported to $OUTPUT_DIR/"

if [ "$EXPORT_ONLY" = true ]; then
    echo ""
    echo "Exported policies:"
    cat "$OUTPUT_DIR/policy_list.txt"
    echo ""
    log_success "Export complete. Review policies in $OUTPUT_DIR/"
    exit 0
fi

# -----------------------------------------------------------------------------
# Step 2: Create new project (if requested)
# -----------------------------------------------------------------------------
if [ -n "$CREATE_NEW_PROJECT" ]; then
    echo ""
    log_info "Creating new project: $CREATE_NEW_PROJECT"
    
    CREATE_CMD="gcloud projects create $CREATE_NEW_PROJECT --name=\"$CREATE_NEW_PROJECT\""
    
    if [ -n "$ORG_ID" ]; then
        CREATE_CMD="$CREATE_CMD --organization=$ORG_ID"
    elif [ -n "$FOLDER_ID" ]; then
        CREATE_CMD="$CREATE_CMD --folder=$FOLDER_ID"
    fi
    
    eval "$CREATE_CMD" || {
        # Project might already exist
        log_warn "Project creation failed. It may already exist. Continuing..."
    }
    
    # Link billing account
    log_info "Linking billing account..."
    gcloud billing projects link "$CREATE_NEW_PROJECT" \
        --billing-account="$BILLING_ACCOUNT" || {
            log_error "Failed to link billing account"
            exit 1
        }
    
    log_success "Project $CREATE_NEW_PROJECT created and billing linked"
fi

# -----------------------------------------------------------------------------
# Step 3: Apply org policies to target project
# -----------------------------------------------------------------------------
echo ""
log_info "Applying org policies to $TARGET_PROJECT..."

APPLIED_COUNT=0
SKIPPED_COUNT=0

for policy_file in "$OUTPUT_DIR"/*.json; do
    [ -f "$policy_file" ] || continue
    
    policy_name=$(basename "$policy_file" .json)
    constraint=$(echo "$policy_name" | sed 's|_|/|g')
    
    # Only apply if policy has custom boolean or list settings (not just inherited)
    if grep -q '"booleanPolicy"\|"listPolicy"' "$policy_file" 2>/dev/null; then
        # Create a new policy file for the target project
        updated_policy=$(cat "$policy_file" | \
            sed "s|projects/${SOURCE_PROJECT}|projects/${TARGET_PROJECT}|g")
        
        echo "$updated_policy" > "$OUTPUT_DIR/apply_${policy_name}.json"
        
        if gcloud resource-manager org-policies set-policy "$OUTPUT_DIR/apply_${policy_name}.json" \
            --project="$TARGET_PROJECT" 2>/dev/null; then
            log_success "Applied: $constraint"
            ((APPLIED_COUNT++))
        else
            log_warn "Failed to apply: $constraint (may be org-level only)"
            ((SKIPPED_COUNT++))
        fi
    else
        ((SKIPPED_COUNT++))
    fi
done

# -----------------------------------------------------------------------------
# Summary
# -----------------------------------------------------------------------------
echo ""
echo "=============================================="
echo "  Summary"
echo "=============================================="
echo "  Policies Applied: $APPLIED_COUNT"
echo "  Policies Skipped: $SKIPPED_COUNT (inherited or org-level)"
echo "  Target Project:   $TARGET_PROJECT"
echo "=============================================="
echo ""

if [ -n "$CREATE_NEW_PROJECT" ]; then
    log_success "New project $CREATE_NEW_PROJECT is ready!"
    echo ""
    echo "Next steps:"
    echo "  1. Set as active project:"
    echo "     gcloud config set project $TARGET_PROJECT"
    echo ""
    echo "  2. Deploy infrastructure:"
    echo "     cd opus && ./scripts/deploy.sh infra dev"
else
    log_success "Policies applied to $TARGET_PROJECT"
fi
