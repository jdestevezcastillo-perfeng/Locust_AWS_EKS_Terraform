# Locust on AWS EKS

Production-grade yet compact toolkit for running distributed [Locust](https://locust.io/) load tests on Amazon EKS. The project provisions AWS networking and cluster resources with Terraform, builds a Locust container, and deploys master/worker workloads plus autoscaling policies with a single manifest.

## What You Get

- Automated VPC, EKS, and ECR provisioning via Terraform 1.0+
- Docker image that bundles Locust scenarios, Prometheus metrics, and helper utilities
- Single `kubernetes/locust-stack.yaml` manifest that creates the namespace, config map, master/worker deployments, services, and HPA
- Optional observability bootstrapper that installs Prometheus + Grafana via Helm

## Quick Start

1. **Install prerequisites**
   - `terraform` ≥ 1.13, `aws-cli` ≥ 2.31, `kubectl` ≥ 1.34, `docker` ≥ 29, and `jq` ≥ 1.8
   - Configure AWS credentials: `aws configure`

2. **Choose an environment**
   - Edit `config/environments/dev|staging|prod/terraform.tfvars` as needed (CIDRs, instance sizes, scaling limits, etc.).

3. **Deploy**

   ```bash
   ./deploy.sh [environment] [image-tag]
   # examples:
   ./deploy.sh
   ./deploy.sh staging v1.2.0
   ```

   The script guides you through region selection, API CIDR restrictions, Terraform apply, Docker build/push, and Kubernetes rollout. On success it prints the LoadBalancer URL for the Locust UI (port 8089).

4. **Destroy**

   ```bash
   ./destroy.sh
   ```

   Removes Kubernetes resources, purges ECR images, tears down Terraform infrastructure, and cleans local artifacts. You will be asked to confirm twice before anything destructive happens.

## Repository Layout

| Path | Purpose |
| ---- | ------- |
| `terraform/` | VPC, subnets, NAT, EKS cluster, node groups, security, and ECR |
| `config/environments/` | Environment-specific Terraform variable files (dev/staging/prod templates) |
| `docker/` | Multi-stage Dockerfile plus entrypoint for running Locust with Prometheus metrics |
| `kubernetes/locust-stack.yaml` | Single source of truth for namespace, ConfigMap, master & worker deployments, services, and HPA |
| `tests/` | Locustfile plus ready-made scenarios (JSONPlaceholder, HTTPBin, and a template) |
| `scripts/common.sh` | Shared bash helpers (colorized logging, validation, wait loops, Terraform/Kubernetes utilities) |
| `scripts/observability/` | Optional Prometheus & Grafana installer/cleanup scripts invoked via `./observability.sh` |

## Customization Cheatsheet

- **AWS capacity / networking** → edit the relevant `config/environments/<env>/terraform.tfvars`
- **Locust destination or defaults** → update `kubernetes/locust-stack.yaml` ConfigMap data block
- **Scenarios** → extend `tests/scenarios/` and switch with `LOCUST_SCENARIO` in the ConfigMap or the Locust UI
- **Worker sizing & scaling** → adjust resources and HPA thresholds inside `kubernetes/locust-stack.yaml`
- **Docker dependencies** → tweak `pyproject.toml` / `docker/Dockerfile` then redeploy to rebuild the image

All manifest changes are applied through the deploy script (which renders the `__LOCUST_IMAGE__` placeholder) or by running:

```bash
IMAGE=123456789012.dkr.ecr.us-east-1.amazonaws.com/locust:latest
sed "s|__LOCUST_IMAGE__|$IMAGE|g" kubernetes/locust-stack.yaml | kubectl apply -f -
```

## Observability (Optional)

Run `./observability.sh setup` after the core deployment to install the full stack (Prometheus + Grafana, VictoriaMetrics for long-term metrics, Loki+Promtail for logs, and Tempo for traces) in the `monitoring` namespace. The script validates Helm/kubectl, wires Prometheus remote-write to VictoriaMetrics, provisions Grafana datasources for every backend, and (optionally) applies a Locust `ServiceMonitor` when `kubernetes/locust-servicemonitor.yaml` is present. For local access you can use `./observability.sh port-forward --both` or port-forward directly:

- `kubectl port-forward -n monitoring svc/prometheus-grafana 3000:80` → Grafana UI (admin/admin123 by default)
- `kubectl port-forward -n monitoring svc/prometheus-grafana-kube-prometheus-prometheus 9090:9090` → Prometheus targets
- `kubectl port-forward -n monitoring svc/victoria-metrics-victoria-metrics-single-server 8428:8428` → VictoriaMetrics query API
- `kubectl port-forward -n monitoring svc/loki-loki 3100:3100` → Loki log API
- `kubectl port-forward -n monitoring svc/tempo-tempo 3200:3200` → Tempo trace API

Clusters with no default StorageClass now fall back to `gp3` automatically (if present). If your
cluster uses a custom class name, export `VICTORIA_STORAGE_CLASS=<storage-class-name>` before running
`./observability.sh setup` so the VictoriaMetrics PVC can bind immediately and Helm does not time out
waiting for volumes.

## Troubleshooting Essentials

- `terraform plan` inside `terraform/` if you need to inspect pending changes.
- `kubectl get pods -n locust` and `kubectl logs -n locust deployment/locust-master` to verify workloads.
- `kubectl get hpa -n locust` to monitor autoscaling decisions.
- If the LoadBalancer hostname takes a while, rerun `kubectl get svc locust-master -n locust -w`.

## Why the Repo Is Smaller Now

- Deployment/destroy logic lives directly in `deploy.sh` and `destroy.sh`, eliminating nine helper scripts and the intermediate `.env.deployment` file.
- Kubernetes manifests collapsed into a single file, making updates and validation faster (and keeping GitHub Actions simpler).
- Documentation trimmed to this README; everything else is either source code or automation.

For a deep-dive architectural summary, see `PRIVATE_OWNER_NOTES.md` (ignored from version control so you can keep personal notes).
