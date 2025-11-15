# Repository Guidelines

## Project Structure & Module Organization
Core infrastructure lives in `terraform/` (VPC, EKS, ECR) and is parameterized via `config/environments/<env>/terraform.tfvars`. Runtime assets sit in `docker/` (Locust image), `kubernetes/locust-stack.yaml` (single manifest for namespace, config map, master/worker, services, HPA), and `scripts/` (shared bash helpers plus observability install). Load scenarios and Locust entrypoints reside in `tests/` with `tests/scenarios/` providing reusable user-behavior modules.

## Build, Test, and Development Commands
- `./deploy.sh [environment] [image-tag]`: orchestrates Terraform apply, Docker build/push, and Kubernetes rollout with placeholder substitution for the Locust image.
- `./destroy.sh [environment]`: removes Kubernetes resources, deletes the push image, and runs `terraform destroy` for the selected environment.
- `terraform -chdir=terraform plan|apply`: run targeted infrastructure changes when you need manual control outside the deployment wrapper.
- `poetry install && poetry run locust -f tests/locustfile.py --headless -u 10 -r 1 --run-time 1m`: execute lightweight scenario validation locally before packaging.
- `./observability.sh setup|cleanup|url|validate`: bootstrap or maintain the optional Prometheus/Grafana stack in `monitoring`; use `url` to get ingress access URLs and `validate` to test all service endpoints.

## Coding Style & Naming Conventions
Python modules target 3.10, keep functions/classes snake_case/PascalCase, and follow PEP 8 line-lengths (88 chars max); prefer dependency declarations in `pyproject.toml`. Bash scripts in `scripts/` stay POSIX-compatible, uppercase for exported variables, and include `set -euo pipefail`. Terraform keeps one logical resource per file and uses `locals` for shared CIDRs; name resources `veeam-<component>-<env>` to match AWS tagging expectations.

## Testing Guidelines
Author traffic models under `tests/scenarios/` and import them through `tests/locustfile.py`; name files after the target system (e.g., `jsonplaceholder.py`). Each scenario should expose a `TaskSet` plus helper weights for clarity. Run `poetry run locust ... --tags smoke` for fast checks and `./deploy.sh <env> <tag>` to exercise autoscaling in-cluster.

## Commit & Pull Request Guidelines
Write commits in the imperative mood with short scopes (e.g., `Update locust manifest`, `Fix session affinity`). Reference Terraform or Kubernetes modules touched when useful. Pull requests must describe the scenario or infrastructure changes, list validation commands (deploy/test/destroy), and link any Jira/GitHub issue. Include screenshots or Grafana panels when modifying observability.

## Security & Configuration Tips
Never hardcode AWS credentials; rely on `aws configure` or `AWS_PROFILE`. Store environment secrets in your shell session before running `./deploy.sh`. CIDR updates and worker limits belong in the matching `config/environments/<env>/terraform.tfvars`; keep prod more restrictive (private subnets, `client_cidr` locked down). Scrub Locust payloads before committing to avoid leaking customer identifiers.
