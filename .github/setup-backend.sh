#!/bin/bash
################################################################################
# Terraform Backend Setup Script
#
# This script creates the required AWS resources for Terraform state management:
# - S3 bucket for state storage (with versioning and encryption)
# - DynamoDB table for state locking
#
# Usage:
#   ./setup-backend.sh [region] [bucket-name] [table-name]
#
# Examples:
#   ./setup-backend.sh
#   ./setup-backend.sh eu-central-1
#   ./setup-backend.sh eu-central-1 my-terraform-state
#   ./setup-backend.sh us-east-1 my-terraform-state terraform-lock
################################################################################

set -euo pipefail

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Default values
DEFAULT_REGION="eu-central-1"
DEFAULT_BUCKET="jd-estevezcastillo-091125"
DEFAULT_TABLE="terraform-state-lock"

# Parse arguments
REGION="${1:-$DEFAULT_REGION}"
STATE_BUCKET="${2:-$DEFAULT_BUCKET}"
LOCK_TABLE="${3:-$DEFAULT_TABLE}"

# Functions
print_header() {
    echo -e "\n${BLUE}========================================${NC}"
    echo -e "${BLUE}$1${NC}"
    echo -e "${BLUE}========================================${NC}\n"
}

print_success() {
    echo -e "${GREEN}✓${NC} $1"
}

print_error() {
    echo -e "${RED}✗${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}⚠${NC} $1"
}

print_info() {
    echo -e "${BLUE}ℹ${NC} $1"
}

check_aws_cli() {
    if ! command -v aws &> /dev/null; then
        print_error "AWS CLI not found. Please install it first."
        exit 1
    fi
    print_success "AWS CLI found"
}

check_aws_credentials() {
    if ! aws sts get-caller-identity &> /dev/null; then
        print_error "AWS credentials not configured or invalid"
        exit 1
    fi

    local account_id=$(aws sts get-caller-identity --query Account --output text)
    local user_arn=$(aws sts get-caller-identity --query Arn --output text)

    print_success "AWS credentials valid"
    print_info "Account ID: ${account_id}"
    print_info "User/Role: ${user_arn}"
}

create_s3_bucket() {
    print_info "Creating S3 bucket: ${STATE_BUCKET}"

    # Check if bucket already exists
    if aws s3 ls "s3://${STATE_BUCKET}" &> /dev/null; then
        print_warning "Bucket ${STATE_BUCKET} already exists, skipping creation"
        return 0
    fi

    # Create bucket (different command for us-east-1 vs other regions)
    if [ "${REGION}" = "us-east-1" ]; then
        aws s3 mb "s3://${STATE_BUCKET}"
    else
        aws s3 mb "s3://${STATE_BUCKET}" --region "${REGION}"
    fi

    print_success "S3 bucket created: ${STATE_BUCKET}"
}

configure_s3_bucket() {
    print_info "Configuring S3 bucket security..."

    # Enable versioning
    print_info "Enabling versioning..."
    aws s3api put-bucket-versioning \
        --bucket "${STATE_BUCKET}" \
        --versioning-configuration Status=Enabled
    print_success "Versioning enabled"

    # Enable encryption
    print_info "Enabling encryption..."
    aws s3api put-bucket-encryption \
        --bucket "${STATE_BUCKET}" \
        --server-side-encryption-configuration '{
            "Rules": [{
                "ApplyServerSideEncryptionByDefault": {
                    "SSEAlgorithm": "AES256"
                },
                "BucketKeyEnabled": true
            }]
        }'
    print_success "Encryption enabled (AES256)"

    # Block public access
    print_info "Blocking public access..."
    aws s3api put-public-access-block \
        --bucket "${STATE_BUCKET}" \
        --public-access-block-configuration \
        "BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true"
    print_success "Public access blocked"

    # Add lifecycle policy for old versions (optional)
    print_info "Configuring lifecycle policy..."
    aws s3api put-bucket-lifecycle-configuration \
        --bucket "${STATE_BUCKET}" \
        --lifecycle-configuration '{
            "Rules": [{
                "ID": "DeleteOldVersions",
                "Status": "Enabled",
                "NoncurrentVersionExpiration": {
                    "NoncurrentDays": 90
                }
            }]
        }'
    print_success "Lifecycle policy configured (old versions deleted after 90 days)"
}

create_dynamodb_table() {
    print_info "Creating DynamoDB table: ${LOCK_TABLE}"

    # Check if table already exists
    if aws dynamodb describe-table --table-name "${LOCK_TABLE}" --region "${REGION}" &> /dev/null; then
        print_warning "Table ${LOCK_TABLE} already exists, skipping creation"
        return 0
    fi

    # Create table
    aws dynamodb create-table \
        --table-name "${LOCK_TABLE}" \
        --attribute-definitions AttributeName=LockID,AttributeType=S \
        --key-schema AttributeName=LockID,KeyType=HASH \
        --billing-mode PAY_PER_REQUEST \
        --region "${REGION}" \
        --tags "Key=Purpose,Value=TerraformStateLocking" "Key=ManagedBy,Value=setup-script" \
        > /dev/null

    print_success "DynamoDB table created: ${LOCK_TABLE}"

    # Wait for table to be active
    print_info "Waiting for table to be active..."
    aws dynamodb wait table-exists --table-name "${LOCK_TABLE}" --region "${REGION}"
    print_success "Table is active"
}

verify_resources() {
    print_info "Verifying created resources..."

    # Verify S3 bucket
    if aws s3 ls "s3://${STATE_BUCKET}" &> /dev/null; then
        print_success "S3 bucket verified: ${STATE_BUCKET}"

        # Check versioning
        local versioning=$(aws s3api get-bucket-versioning --bucket "${STATE_BUCKET}" --query Status --output text 2>/dev/null || echo "")
        if [ "${versioning}" = "Enabled" ]; then
            print_success "Versioning is enabled"
        else
            print_warning "Versioning is not enabled"
        fi

        # Check encryption
        if aws s3api get-bucket-encryption --bucket "${STATE_BUCKET}" &> /dev/null; then
            print_success "Encryption is enabled"
        else
            print_warning "Encryption is not enabled"
        fi
    else
        print_error "S3 bucket verification failed"
        return 1
    fi

    # Verify DynamoDB table
    if aws dynamodb describe-table --table-name "${LOCK_TABLE}" --region "${REGION}" &> /dev/null; then
        print_success "DynamoDB table verified: ${LOCK_TABLE}"

        local status=$(aws dynamodb describe-table --table-name "${LOCK_TABLE}" --region "${REGION}" --query Table.TableStatus --output text)
        print_info "Table status: ${status}"
    else
        print_error "DynamoDB table verification failed"
        return 1
    fi
}

print_summary() {
    print_header "Setup Complete!"

    echo -e "${GREEN}AWS backend resources have been created successfully!${NC}\n"

    echo -e "${BLUE}Configuration Details:${NC}"
    echo -e "  Region:          ${REGION}"
    echo -e "  S3 Bucket:       ${STATE_BUCKET}"
    echo -e "  DynamoDB Table:  ${LOCK_TABLE}"
    echo ""

    echo -e "${BLUE}Next Steps:${NC}"
    echo ""
    echo -e "${YELLOW}1. Configure GitHub Secrets${NC}"
    echo "   Go to: Settings > Secrets and variables > Actions"
    echo ""
    echo "   Add these secrets:"
    echo "   - AWS_ACCESS_KEY_ID       = <your-access-key>"
    echo "   - AWS_SECRET_ACCESS_KEY   = <your-secret-key>"
    echo "   - AWS_REGION              = ${REGION}"
    echo "   - TF_STATE_BUCKET         = ${STATE_BUCKET}"
    echo "   - TF_STATE_LOCK_TABLE     = ${LOCK_TABLE}"
    echo ""

    echo -e "${YELLOW}2. Test Terraform Backend${NC}"
    echo "   cd terraform"
    echo "   terraform init \\"
    echo "     -backend-config=\"bucket=${STATE_BUCKET}\" \\"
    echo "     -backend-config=\"key=test/terraform.tfstate\" \\"
    echo "     -backend-config=\"region=${REGION}\" \\"
    echo "     -backend-config=\"dynamodb_table=${LOCK_TABLE}\""
    echo ""

    echo -e "${YELLOW}3. Run GitHub Actions Workflow${NC}"
    echo "   Actions > Deploy Infrastructure > Run workflow"
    echo ""

    echo -e "${BLUE}Documentation:${NC}"
    echo "   - Quick Start: .github/QUICK_START.md"
    echo "   - Setup Guide: .github/GITHUB_ACTIONS_SETUP.md"
    echo "   - Secrets:     .github/SECRETS_SETUP.md"
    echo ""

    echo -e "${GREEN}Setup completed successfully!${NC}\n"
}

# Main execution
main() {
    print_header "Terraform Backend Setup"

    echo -e "${BLUE}Configuration:${NC}"
    echo "  Region:          ${REGION}"
    echo "  S3 Bucket:       ${STATE_BUCKET}"
    echo "  DynamoDB Table:  ${LOCK_TABLE}"
    echo ""

    # Confirm with user
    read -p "Proceed with this configuration? (y/N): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        print_warning "Setup cancelled by user"
        exit 0
    fi

    # Run setup steps
    print_header "Step 1: Checking Prerequisites"
    check_aws_cli
    check_aws_credentials

    print_header "Step 2: Creating S3 Bucket"
    create_s3_bucket
    configure_s3_bucket

    print_header "Step 3: Creating DynamoDB Table"
    create_dynamodb_table

    print_header "Step 4: Verifying Resources"
    verify_resources

    # Print summary
    print_summary
}

# Run main function
main "$@"
