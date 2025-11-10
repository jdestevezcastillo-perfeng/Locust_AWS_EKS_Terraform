#!/bin/bash
#
# Validate GitHub Actions Workflows
# This script checks workflow files for common issues and validates configuration
#

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/../../" && pwd)"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

print_header() {
    echo -e "${BLUE}========================================${NC}"
    echo -e "${BLUE}$1${NC}"
    echo -e "${BLUE}========================================${NC}"
}

print_success() {
    echo -e "${GREEN}✓ $1${NC}"
}

print_error() {
    echo -e "${RED}✗ $1${NC}"
}

print_warning() {
    echo -e "${YELLOW}! $1${NC}"
}

print_info() {
    echo -e "${BLUE}→ $1${NC}"
}

# Track validation status
VALIDATION_ERRORS=0

print_header "GitHub Actions Workflow Validation"

# Check if running in project root
cd "$PROJECT_ROOT"
print_info "Project root: $PROJECT_ROOT"

# -------------------------------------------------------------------------
# 1. Check Workflow Files Exist
# -------------------------------------------------------------------------
print_header "Checking Workflow Files"

WORKFLOWS=(
    "deploy-application.yml"
)

for workflow in "${WORKFLOWS[@]}"; do
    if [ -f ".github/workflows/$workflow" ]; then
        print_success "Found: $workflow"
    else
        print_error "Missing: $workflow"
        ((VALIDATION_ERRORS++))
    fi
done

# -------------------------------------------------------------------------
# 2. Check Composite Action
# -------------------------------------------------------------------------
print_header "Checking Composite Action"

if [ -f ".github/actions/setup-prerequisites/action.yml" ]; then
    print_success "Found: setup-prerequisites action"
else
    print_error "Missing: setup-prerequisites action"
    ((VALIDATION_ERRORS++))
fi

# -------------------------------------------------------------------------
# 3. Validate YAML Syntax
# -------------------------------------------------------------------------
print_header "Validating YAML Syntax"

# Check if yamllint is available
if command -v yamllint &> /dev/null; then
    for workflow in "${WORKFLOWS[@]}"; do
        if yamllint -d relaxed ".github/workflows/$workflow" 2>/dev/null; then
            print_success "YAML valid: $workflow"
        else
            print_warning "YAML issues in: $workflow (non-critical)"
        fi
    done
else
    print_warning "yamllint not installed - skipping YAML validation"
    print_info "Install with: pip install yamllint"
fi

# -------------------------------------------------------------------------
# 4. Check Required Project Files
# -------------------------------------------------------------------------
print_header "Checking Required Project Files"

REQUIRED_FILES=(
    "docker/Dockerfile"
    "terraform/main.tf"
    "terraform/variables.tf"
    "terraform/outputs.tf"
    "kubernetes/base/namespace.yaml"
    "kubernetes/base/configmap.yaml"
    "kubernetes/base/master-deployment.yaml"
    "kubernetes/base/master-service.yaml"
    "kubernetes/base/worker-deployment.yaml"
    "kubernetes/base/worker-hpa.yaml"
)

for file in "${REQUIRED_FILES[@]}"; do
    if [ -f "$file" ]; then
        print_success "Found: $file"
    else
        print_error "Missing: $file"
        ((VALIDATION_ERRORS++))
    fi
done

# -------------------------------------------------------------------------
# 5. Check Kubernetes Manifests
# -------------------------------------------------------------------------
print_header "Validating Kubernetes Manifests"

# Check if kubectl is available
if command -v kubectl &> /dev/null; then
    for manifest in kubernetes/base/*.yaml; do
        if kubectl apply --dry-run=client -f "$manifest" &>/dev/null; then
            print_success "Valid K8s manifest: $(basename $manifest)"
        else
            print_error "Invalid K8s manifest: $(basename $manifest)"
            ((VALIDATION_ERRORS++))
        fi
    done
else
    print_warning "kubectl not installed - skipping K8s validation"
    print_info "Install from: https://kubernetes.io/docs/tasks/tools/"
fi

# -------------------------------------------------------------------------
# 6. Check Dockerfile
# -------------------------------------------------------------------------
print_header "Validating Dockerfile"

if [ -f "docker/Dockerfile" ]; then
    # Check if hadolint is available
    if command -v hadolint &> /dev/null; then
        if hadolint docker/Dockerfile; then
            print_success "Dockerfile passes hadolint"
        else
            print_warning "Dockerfile has hadolint warnings"
        fi
    else
        print_warning "hadolint not installed - skipping Dockerfile validation"
        print_info "Install from: https://github.com/hadolint/hadolint"
    fi

    # Basic checks
    if grep -q "FROM" docker/Dockerfile; then
        print_success "Dockerfile has valid FROM instruction"
    else
        print_error "Dockerfile missing FROM instruction"
        ((VALIDATION_ERRORS++))
    fi
fi

# -------------------------------------------------------------------------
# 7. Check for Required GitHub Secrets Documentation
# -------------------------------------------------------------------------
print_header "Checking Documentation"

if [ -f ".github/workflows/README.md" ]; then
    print_success "Workflow documentation exists"

    # Check if documentation mentions required secrets
    if grep -q "AWS_ACCESS_KEY_ID" .github/workflows/README.md; then
        print_success "Documentation includes AWS_ACCESS_KEY_ID"
    else
        print_warning "Documentation missing AWS_ACCESS_KEY_ID reference"
    fi

    if grep -q "AWS_SECRET_ACCESS_KEY" .github/workflows/README.md; then
        print_success "Documentation includes AWS_SECRET_ACCESS_KEY"
    else
        print_warning "Documentation missing AWS_SECRET_ACCESS_KEY reference"
    fi
else
    print_warning "Workflow documentation (.github/workflows/README.md) not found"
fi

# -------------------------------------------------------------------------
# 8. Validate Workflow Inputs and Outputs
# -------------------------------------------------------------------------
print_header "Analyzing Workflow Structure"

print_info "Checking deploy-application.yml..."

if [ -f ".github/workflows/deploy-application.yml" ]; then
    # Check for workflow_dispatch trigger
    if grep -q "workflow_dispatch:" .github/workflows/deploy-application.yml; then
        print_success "Has manual trigger (workflow_dispatch)"
    else
        print_warning "Missing manual trigger"
    fi

    # Check for workflow_call trigger
    if grep -q "workflow_call:" .github/workflows/deploy-application.yml; then
        print_success "Can be called by other workflows (workflow_call)"
    else
        print_warning "Cannot be called by other workflows"
    fi

    # Check for required jobs
    REQUIRED_JOBS=("validate" "build-push" "deploy-kubernetes")
    for job in "${REQUIRED_JOBS[@]}"; do
        if grep -q "$job:" .github/workflows/deploy-application.yml; then
            print_success "Has job: $job"
        else
            print_error "Missing job: $job"
            ((VALIDATION_ERRORS++))
        fi
    done
fi

# -------------------------------------------------------------------------
# 9. Security Checks
# -------------------------------------------------------------------------
print_header "Security Validation"

# Check for hardcoded secrets (common patterns)
print_info "Scanning for hardcoded secrets..."

SECRETS_FOUND=0
for file in .github/workflows/*.yml; do
    if grep -E "(AKIA[0-9A-Z]{16}|aws_secret_access_key.*=.*[A-Za-z0-9/+=]{40})" "$file" &>/dev/null; then
        print_error "Potential hardcoded AWS credentials in $(basename $file)"
        ((SECRETS_FOUND++))
        ((VALIDATION_ERRORS++))
    fi
done

if [ $SECRETS_FOUND -eq 0 ]; then
    print_success "No hardcoded secrets detected"
fi

# Check for use of GitHub secrets
if grep -q '\${{ secrets\.' .github/workflows/deploy-application.yml; then
    print_success "Uses GitHub secrets properly"
else
    print_warning "May not be using GitHub secrets"
fi

# -------------------------------------------------------------------------
# 10. Best Practices Check
# -------------------------------------------------------------------------
print_header "Best Practices Validation"

# Check for timeout configuration
if grep -q "timeout-minutes:" .github/workflows/deploy-application.yml; then
    print_success "Jobs have timeout configuration"
else
    print_warning "No timeout configuration found"
fi

# Check for artifact upload
if grep -q "upload-artifact" .github/workflows/deploy-application.yml; then
    print_success "Uploads artifacts for debugging"
else
    print_warning "No artifact uploads configured"
fi

# Check for security scanning
if grep -q "trivy" .github/workflows/deploy-application.yml; then
    print_success "Includes container security scanning"
else
    print_warning "No container security scanning configured"
fi

# -------------------------------------------------------------------------
# Final Summary
# -------------------------------------------------------------------------
print_header "Validation Summary"

if [ $VALIDATION_ERRORS -eq 0 ]; then
    print_success "All validations passed!"
    echo ""
    print_info "Next steps:"
    echo "  1. Configure GitHub secrets (see .github/workflows/README.md)"
    echo "  2. Ensure AWS infrastructure is deployed"
    echo "  3. Test workflow manually from GitHub Actions UI"
    exit 0
else
    print_error "Validation failed with $VALIDATION_ERRORS error(s)"
    echo ""
    print_info "Please fix the errors above before using the workflows"
    exit 1
fi
