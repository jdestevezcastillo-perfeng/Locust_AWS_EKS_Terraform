# GitHub Actions Quick Start Guide

This guide will help you quickly set up and use the GitHub Actions workflows for deploying the Locust load testing application on AWS EKS.

## 5-Minute Setup

### Step 1: Configure GitHub Secrets (2 minutes)

1. Go to your GitHub repository
2. Navigate to: **Settings** → **Secrets and variables** → **Actions**
3. Click **New repository secret** and add:

```
Name: AWS_ACCESS_KEY_ID
Value: <your-aws-access-key-id>

Name: AWS_SECRET_ACCESS_KEY
Value: <your-aws-secret-access-key>

Name: AWS_REGION (optional)
Value: eu-central-1  # or your preferred region
```

### Step 2: Ensure Infrastructure is Deployed (prerequisite)

Before running the application deployment workflow, ensure your AWS infrastructure exists:

```bash
# From your local machine
cd /home/lostborion/Documents/veeam-extended

# Deploy infrastructure if not already done
./deploy.sh

# Or manually:
cd terraform
terraform init
terraform apply
```

### Step 3: Run the Workflow (1 minute)

1. Go to **Actions** tab in GitHub
2. Select **Deploy Locust Application**
3. Click **Run workflow**
4. Configure:
   - Environment: `dev`
   - Image Tag: (leave empty for auto-generation)
   - Skip Tests: unchecked
5. Click **Run workflow**

### Step 4: Access Locust (1 minute)

Once deployment completes:

1. Check the **Summary** tab in the workflow run
2. Find the LoadBalancer URL
3. Open in browser: `http://<loadbalancer-url>:8089`

If LoadBalancer is still provisioning:
```bash
kubectl port-forward -n locust svc/locust-master 8089:8089
# Then open: http://localhost:8089
```

## Common Tasks

### Deploy to Different Environment

```yaml
# Manual trigger via GitHub UI
Environment: staging  # or prod
Image Tag: v1.0.0    # specific version
```

### Deploy Specific Version

```yaml
Environment: prod
Image Tag: v2.1.3
Skip Tests: false
```

### Quick Rollback

1. Go to **Actions** tab
2. Find previous successful deployment
3. Click **Re-run all jobs**

Or manually:
```bash
# Set image to previous version
kubectl set image deployment/locust-master \
  locust=<ecr-repo-url>:previous-tag -n locust

kubectl set image deployment/locust-worker \
  locust=<ecr-repo-url>:previous-tag -n locust
```

### View Deployment Status

```bash
# Quick status check
kubectl get all -n locust

# Detailed pod status
kubectl get pods -n locust -o wide

# View logs
kubectl logs -f deployment/locust-master -n locust
kubectl logs -f deployment/locust-worker -n locust

# Check HPA
kubectl get hpa -n locust
```

### Scale Workers Manually

```bash
# Scale to 10 workers
kubectl scale deployment locust-worker -n locust --replicas=10

# Or update HPA
kubectl patch hpa locust-worker-hpa -n locust \
  -p '{"spec":{"maxReplicas":30}}'
```

## Workflow Output Artifacts

Each workflow run generates downloadable artifacts:

1. **image-metadata.json**
   - Image URI and tag
   - Git commit info
   - Build timestamp

2. **deployment-summary.md**
   - Environment details
   - Kubernetes resource status
   - Access URLs
   - Quick commands

3. **verification-report.md**
   - Post-deployment checks
   - Pod status
   - Recent events

Download from: **Actions** → **Workflow Run** → **Artifacts** (bottom of page)

## Troubleshooting Quick Reference

### Problem: Workflow fails at validation stage

**Solution**:
```bash
# Check Terraform state exists
cd terraform
terraform state list

# If empty, deploy infrastructure first
terraform apply
```

### Problem: ECR authentication failed

**Solution**:
- Verify GitHub secrets are correct
- Check AWS IAM permissions
- Ensure AWS_REGION matches your infrastructure

### Problem: kubectl cannot connect

**Solution**:
```bash
# Locally verify cluster exists
aws eks list-clusters --region eu-central-1

# Update kubeconfig
aws eks update-kubeconfig \
  --name <cluster-name> \
  --region eu-central-1
```

### Problem: Pods not starting

**Solution**:
```bash
# Check pod status and events
kubectl describe pod -n locust <pod-name>

# View logs
kubectl logs -n locust <pod-name>

# Common issues:
# - Image pull errors: Check ECR permissions
# - Resource limits: Check node capacity
# - ConfigMap missing: Verify configmap.yaml applied
```

### Problem: LoadBalancer not getting IP

**Solution**:
- Wait 2-5 minutes for AWS provisioning
- Use port-forward as temporary solution:
  ```bash
  kubectl port-forward -n locust svc/locust-master 8089:8089
  ```
- Check AWS Load Balancer in EC2 console

## Monitoring Deployments

### Real-time Monitoring

```bash
# Watch pod status
watch kubectl get pods -n locust

# Follow master logs
kubectl logs -f deployment/locust-master -n locust

# Follow worker logs
kubectl logs -f deployment/locust-worker -n locust

# Watch HPA scaling
watch kubectl get hpa -n locust
```

### GitHub Actions Monitoring

1. **Actions** tab shows all workflow runs
2. Click run to see detailed logs
3. Use **Summary** tab for quick overview
4. Download artifacts for offline analysis

## Best Practices

### 1. Use Environment-Specific Tags

```
dev: Auto-generated tags (dev-sha-timestamp)
staging: Release candidates (rc-v1.2.3)
prod: Semantic versions (v1.2.3)
```

### 2. Test Before Production

```
dev → staging → prod
```

Always test in dev/staging before deploying to production.

### 3. Monitor After Deployment

- Check pods are running: `kubectl get pods -n locust`
- Verify LoadBalancer: `kubectl get svc -n locust`
- Access UI and run test load scenario
- Monitor logs for errors

### 4. Maintain Deployment History

- Keep artifacts from production deployments
- Document significant changes in commit messages
- Tag production releases in git

### 5. Cost Management

```bash
# Scale down dev/staging when not in use
kubectl scale deployment locust-worker -n locust --replicas=1

# Or destroy entire environment
cd terraform
terraform destroy
```

## Emergency Procedures

### Emergency Rollback

```bash
# Find previous working image tag
kubectl describe deployment locust-master -n locust | grep Image

# Rollback to previous version
kubectl rollout undo deployment/locust-master -n locust
kubectl rollout undo deployment/locust-worker -n locust

# Or via specific revision
kubectl rollout history deployment/locust-master -n locust
kubectl rollout undo deployment/locust-master -n locust --to-revision=2
```

### Emergency Scale-Down

```bash
# Scale workers to minimum
kubectl scale deployment locust-worker -n locust --replicas=0

# Or pause HPA
kubectl patch hpa locust-worker-hpa -n locust \
  -p '{"spec":{"maxReplicas":0}}'
```

### Emergency Stop

```bash
# Delete all Locust resources
kubectl delete namespace locust

# This removes:
# - All deployments
# - All services
# - All pods
# - LoadBalancer (stops AWS charges)
```

## Additional Resources

- **Detailed Documentation**: See `.github/workflows/README.md`
- **AWS Setup Guide**: See `AWS_SETUP.md` in project root
- **Kubernetes Manifests**: See `kubernetes/base/` directory
- **Deployment Scripts**: See `scripts/deploy/` directory

## Getting Help

1. Check workflow logs in GitHub Actions
2. Review deployment artifacts
3. Check Kubernetes events: `kubectl get events -n locust`
4. Review project documentation
5. Check AWS console for infrastructure status

---

**Quick Links**:
- [Workflow Documentation](.github/workflows/README.md)
- [Project README](../README.md)
- [AWS Setup Guide](../AWS_SETUP.md)

**Last Updated**: 2025-01-09
