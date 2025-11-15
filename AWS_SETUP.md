# AWS Setup Guide for Locust Deployment

If you cloned this project and want to deploy it, follow this guide to configure AWS credentials.

## Step 1: Create AWS IAM User

1. Go to [AWS IAM Console](https://console.aws.amazon.com/iam/)
2. Click **Users** → **Create user**
3. Enter a name (e.g., `locust-deployment`)
4. Click **Next**
5. On "Set permissions" page:
   - Select **Attach policies directly**
   - Search for and select these policies:
     - `AdministratorAccess` (for easy setup; restrict in production)
     - OR individually select:
       - `AmazonEKSFullAccess`
       - `AmazonEC2FullAccess`
       - `AmazonVPCFullAccess`
       - `IAMFullAccess`
       - `AmazonEC2ContainerRegistryFullAccess`
6. Click **Next** → **Create user**

## Step 2: Generate Access Keys

1. Click on the newly created user
2. Go to **Security credentials** tab
3. Click **Create access key**
4. Select **Command Line Interface (CLI)**
5. Accept the warning
6. Click **Create access key**
7. **Copy and save the credentials**:
   - Access Key ID
   - Secret Access Key

⚠️ **IMPORTANT:** This is the only time you'll see the secret key. Save it somewhere safe!

## Step 3: Configure AWS CLI

Run this command:

```bash
aws configure
```

You'll be prompted for:

```
AWS Access Key ID: [paste the Access Key ID]
AWS Secret Access Key: [paste the Secret Access Key]
Default region name: eu-central-1
Default output format: json
```

**Recommended regions:**
- `eu-central-1` (Frankfurt) - Default
- `us-east-1` (Virginia)
- `us-west-2` (Oregon)
- `eu-west-1` (Ireland)

## Step 4: Verify Configuration

Test your setup:

```bash
aws sts get-caller-identity
```

Should output something like:

```json
{
    "UserId": "AIDAI...",
    "Account": "123456789012",
    "Arn": "arn:aws:iam::123456789012:user/locust-deployment"
}
```

## Step 5: Deploy

Now you can run the deployment:

```bash
./deploy.sh
```

The script will:
1. ✅ Validate your AWS credentials
2. ✅ Ask you to select a region
3. ✅ Deploy the infrastructure
4. ✅ Show you access URLs

## What the Script Does

**SECURITY NOTE:** The deploy script does **NOT** ask you to paste credentials.

Instead:
1. It checks if AWS credentials are already configured via `aws configure`
2. If missing, it guides you to configure them properly
3. It asks you to select a region interactively
4. All credentials stay in `~/.aws/credentials` (NOT in the project)

This is a security best practice - credentials are never stored in the project or passed as arguments.

## Troubleshooting

### "AWS credentials not found or invalid"

**Solution:**
```bash
aws configure
# Then run ./deploy.sh again
```

### "Unable to locate credentials"

**Solution:**
```bash
# Check if credentials are set
aws sts get-caller-identity

# If that fails, reconfigure:
aws configure
```

### "User is not authorized to perform: iam:GetUser"

**Solution:**
Your IAM user doesn't have proper permissions. Make sure you attached:
- `AdministratorAccess` OR
- All 5 policies listed in Step 1

### "No valid AWS credentials found"

**Solution:**
```bash
# Verify credentials file exists
cat ~/.aws/credentials

# Should show:
# [default]
# aws_access_key_id = AKIA...
# aws_secret_access_key = ...
```

## Security Best Practices

1. **Never commit credentials to git:**
   - AWS credentials are already in `.gitignore`
   - Check: `grep "aws" .gitignore`

2. **Rotate credentials regularly:**
   - Go to IAM → Users → Your user → Security credentials
   - Delete old access keys
   - Create new ones

3. **Use least-privilege policies:**
   - In production, don't use `AdministratorAccess`
   - Create a role with only needed permissions

4. **Enable MFA (Multi-Factor Authentication):**
   - For additional security
   - Recommended for production accounts

## Cost Awareness

After deployment, resources cost ~$0.34/hour. **Always run cleanup when done:**

```bash
./destroy.sh
```

## Next Steps

1. ✅ Configure AWS credentials
2. ✅ Run `./deploy.sh`
3. ✅ Access Locust at the provided URL
4. ✅ Run your load tests
5. ✅ Run `./destroy.sh` to avoid charges

## Support

For AWS-specific issues:
- [AWS CLI Documentation](https://docs.aws.amazon.com/cli/)
- [IAM User Guide](https://docs.aws.amazon.com/iam/)
- [EKS User Guide](https://docs.aws.amazon.com/eks/)

For deployment issues:
- See [README.md](README.md) for architecture and deployment overview
- Run `./observability.sh url` to get access URLs after deployment
- See the Troubleshooting section in [README.md](README.md#troubleshooting)
