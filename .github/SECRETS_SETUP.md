# GitHub Secrets Setup - Quick Reference

## Required Secrets

Configure these secrets before running the infrastructure deployment workflow.

### Navigation

1. Go to your GitHub repository
2. Click **Settings** tab
3. Click **Secrets and variables** > **Actions**
4. Click **New repository secret**

---

## Secrets to Configure

### 1. AWS_ACCESS_KEY_ID

**Value**: Your AWS IAM access key ID

```
Example: AKIAIOSFODNN7EXAMPLE
```

**How to get**:
```bash
# If you have AWS CLI configured:
cat ~/.aws/credentials

# Or create a new access key in AWS Console:
# IAM > Users > [your-user] > Security credentials > Create access key
```

---

### 2. AWS_SECRET_ACCESS_KEY

**Value**: Your AWS IAM secret access key

```
Example: wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY
```

**How to get**: Same as AWS_ACCESS_KEY_ID above (shown only once during creation)

---

### 3. AWS_REGION

**Value**: AWS region for deployment

```
Default: eu-central-1
Other options: us-east-1, us-west-2, eu-west-1, ap-southeast-1, etc.
```

---

### 4. TF_STATE_BUCKET

**Value**: S3 bucket name for Terraform state storage

```
Example: my-company-terraform-state
```

**Create the bucket**:
```bash
# Create bucket
aws s3 mb s3://my-company-terraform-state --region eu-central-1

# Enable versioning
aws s3api put-bucket-versioning \
  --bucket my-company-terraform-state \
  --versioning-configuration Status=Enabled

# Enable encryption
aws s3api put-bucket-encryption \
  --bucket my-company-terraform-state \
  --server-side-encryption-configuration '{
    "Rules": [{
      "ApplyServerSideEncryptionByDefault": {
        "SSEAlgorithm": "AES256"
      }
    }]
  }'

# Block public access
aws s3api put-public-access-block \
  --bucket my-company-terraform-state \
  --public-access-block-configuration \
  "BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true"
```

---

### 5. TF_STATE_LOCK_TABLE

**Value**: DynamoDB table name for Terraform state locking

```
Default: terraform-state-lock
```

**Create the table**:
```bash
aws dynamodb create-table \
  --table-name terraform-state-lock \
  --attribute-definitions AttributeName=LockID,AttributeType=S \
  --key-schema AttributeName=LockID,KeyType=HASH \
  --billing-mode PAY_PER_REQUEST \
  --region eu-central-1
```

---

## Optional Secrets

### AWS_SESSION_TOKEN

**Value**: AWS session token (only needed for temporary credentials)

**When required**:
- Using AWS SSO
- Using assumed IAM roles
- Using temporary credentials from AWS STS

---

## Verification

After configuring secrets, verify they're set correctly:

1. Go to **Settings** > **Secrets and variables** > **Actions**
2. You should see all 5 required secrets listed
3. Click the **Update** button on any secret to verify its value (but don't change it)

---

## Quick Setup Script

Create all AWS resources in one go:

```bash
#!/bin/bash
set -e

REGION="eu-central-1"
STATE_BUCKET="my-company-terraform-state"
LOCK_TABLE="terraform-state-lock"

echo "Creating Terraform state backend..."

# Create S3 bucket
echo "Creating S3 bucket: ${STATE_BUCKET}"
aws s3 mb "s3://${STATE_BUCKET}" --region "${REGION}"

# Configure bucket
echo "Configuring bucket security..."
aws s3api put-bucket-versioning \
  --bucket "${STATE_BUCKET}" \
  --versioning-configuration Status=Enabled

aws s3api put-bucket-encryption \
  --bucket "${STATE_BUCKET}" \
  --server-side-encryption-configuration '{
    "Rules": [{
      "ApplyServerSideEncryptionByDefault": {
        "SSEAlgorithm": "AES256"
      }
    }]
  }'

aws s3api put-public-access-block \
  --bucket "${STATE_BUCKET}" \
  --public-access-block-configuration \
  "BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true"

# Create DynamoDB table
echo "Creating DynamoDB table: ${LOCK_TABLE}"
aws dynamodb create-table \
  --table-name "${LOCK_TABLE}" \
  --attribute-definitions AttributeName=LockID,AttributeType=S \
  --key-schema AttributeName=LockID,KeyType=HASH \
  --billing-mode PAY_PER_REQUEST \
  --region "${REGION}"

echo ""
echo "Setup complete!"
echo ""
echo "Configure these GitHub secrets:"
echo "  TF_STATE_BUCKET: ${STATE_BUCKET}"
echo "  TF_STATE_LOCK_TABLE: ${LOCK_TABLE}"
echo "  AWS_REGION: ${REGION}"
echo ""
echo "Also configure:"
echo "  AWS_ACCESS_KEY_ID: [your-access-key]"
echo "  AWS_SECRET_ACCESS_KEY: [your-secret-key]"
```

Save this as `setup-backend.sh`, make it executable with `chmod +x setup-backend.sh`, and run it.

---

## Secrets Checklist

Before running the workflow, verify:

- [ ] AWS_ACCESS_KEY_ID is set
- [ ] AWS_SECRET_ACCESS_KEY is set
- [ ] AWS_REGION is set
- [ ] TF_STATE_BUCKET is set and the bucket exists
- [ ] TF_STATE_LOCK_TABLE is set and the table exists
- [ ] S3 bucket has versioning enabled
- [ ] S3 bucket has encryption enabled
- [ ] S3 bucket blocks public access
- [ ] IAM user/role has required permissions
- [ ] DynamoDB table is created and accessible

---

## Testing Secrets

Test your configuration locally before running in GitHub Actions:

```bash
# Export secrets as environment variables
export AWS_ACCESS_KEY_ID="your-key"
export AWS_SECRET_ACCESS_KEY="your-secret"
export AWS_REGION="eu-central-1"
export TF_STATE_BUCKET="my-company-terraform-state"
export TF_STATE_LOCK_TABLE="terraform-state-lock"

# Test AWS credentials
aws sts get-caller-identity

# Test S3 access
aws s3 ls "s3://${TF_STATE_BUCKET}"

# Test DynamoDB access
aws dynamodb describe-table --table-name "${TF_STATE_LOCK_TABLE}"

# Test Terraform backend
cd terraform
terraform init \
  -backend-config="bucket=${TF_STATE_BUCKET}" \
  -backend-config="key=test/terraform.tfstate" \
  -backend-config="region=${AWS_REGION}" \
  -backend-config="dynamodb_table=${TF_STATE_LOCK_TABLE}"
```

If all commands succeed, your secrets are configured correctly!

---

## Security Notes

1. **Never commit secrets** to the repository
2. **Rotate access keys** regularly (every 90 days recommended)
3. **Use IAM roles** when possible instead of long-lived access keys
4. **Enable MFA** on the IAM user that owns these credentials
5. **Limit permissions** to only what's required (principle of least privilege)
6. **Monitor usage** with CloudTrail and set up alerts for unusual activity
7. **Use environment protection** for production deployments (requires manual approval)

---

## Troubleshooting

### "Could not load credentials"

- Verify AWS_ACCESS_KEY_ID and AWS_SECRET_ACCESS_KEY are set
- Check for typos or extra spaces in secret values
- Ensure the IAM user exists and credentials are active

### "Access Denied" errors

- Verify IAM permissions (see GITHUB_ACTIONS_SETUP.md)
- Check service control policies (SCPs) if using AWS Organizations
- Ensure the region is correct and services are available

### "Bucket does not exist"

- Verify TF_STATE_BUCKET name is correct (no typos)
- Ensure the bucket was created in the correct region
- Check bucket name doesn't contain invalid characters

### "Table not found"

- Verify TF_STATE_LOCK_TABLE name is correct
- Ensure the table was created in the correct region
- Check table status in AWS Console (should be "Active")

---

## Need Help?

If you encounter issues:

1. Check the GitHub Actions workflow logs for detailed error messages
2. Review the AWS CloudTrail logs for API call failures
3. Verify IAM permissions match the required policy
4. Test credentials locally using the commands above
5. Open an issue in the repository with error details
