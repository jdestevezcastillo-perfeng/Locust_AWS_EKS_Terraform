# Development defaults – AWS Free Tier compatible configuration
aws_region  = "eu-central-1"
environment = "dev"

vpc_cidr             = "10.0.0.0/16"
public_subnet_cidrs  = ["10.0.1.0/24", "10.0.2.0/24"]
private_subnet_cidrs = ["10.0.10.0/24", "10.0.20.0/24"]

cluster_name                         = "locust-dev-cluster"
kubernetes_version                   = "1.34"
cluster_endpoint_public_access       = true
cluster_endpoint_public_access_cidrs = ["0.0.0.0/0"]  # Overridden during deploy for safety

# EKS Locust Master Node Group Configuration
# Master needs stability (ON_DEMAND) and sufficient resources
locust_master_node_group_name  = "locust-master-dev-nodes"
locust_master_instance_type    = "t3.small"      # 2 vCPU, 2GB RAM - Free tier eligible
locust_master_capacity_type    = "ON_DEMAND"     # Stable, not SPOT
locust_master_disk_size        = 20
locust_master_desired_capacity = 1
locust_master_min_capacity     = 1
locust_master_max_capacity     = 2  # HA failover only

# EKS Locust Worker Node Group Configuration
# Workers can use SPOT for cost savings, scale dynamically
node_group_name      = "locust-worker-dev-nodes"
node_instance_type   = "t3.small"   # 2 vCPU, 2GB RAM - Free tier eligible
node_capacity_type   = "SPOT"       # 70% cost savings
node_disk_size       = 20
desired_capacity     = 3
min_capacity         = 3
max_capacity         = 10  # Can scale up based on HPA

# EKS Monitoring Node Group Configuration
monitoring_node_group_name   = "monitoring-dev-nodes"
monitoring_instance_type     = "m7i-flex.large"  # 2 vCPU, 4GB RAM
monitoring_capacity_type     = "ON_DEMAND"
monitoring_disk_size         = 30
monitoring_desired_capacity  = 2
monitoring_min_capacity      = 2
monitoring_max_capacity      = 4

ecr_repository_name = "locust-dev-load-tests"
ecr_scan_on_push    = false

log_retention_days = 7
