# Staging environment – mirrors production sizing without full scale
aws_region  = "us-east-1"
environment = "staging"

vpc_cidr             = "10.10.0.0/16"
public_subnet_cidrs  = ["10.10.1.0/24", "10.10.2.0/24"]
private_subnet_cidrs = ["10.10.10.0/24", "10.10.20.0/24"]

cluster_name                         = "locust-staging-cluster"
kubernetes_version                   = "1.34"
cluster_endpoint_public_access       = true
cluster_endpoint_public_access_cidrs = ["203.0.113.0/32"]  # Replace with real office/VPN CIDR

# EKS Locust Master Node Group Configuration
locust_master_node_group_name  = "locust-master-staging-nodes"
locust_master_instance_type    = "t3.medium"     # Larger for staging
locust_master_capacity_type    = "ON_DEMAND"     # Stable master
locust_master_disk_size        = 40
locust_master_desired_capacity = 1
locust_master_min_capacity     = 1
locust_master_max_capacity     = 2

# EKS Locust Worker Node Group Configuration
node_group_name      = "locust-worker-staging-nodes"
node_instance_type   = "c5.large"        # Better performance for staging
node_capacity_type   = "SPOT"            # Cost savings
node_disk_size       = 40
desired_capacity     = 4
min_capacity         = 3
max_capacity         = 15

# EKS Monitoring Node Group Configuration
monitoring_node_group_name   = "monitoring-staging-nodes"
monitoring_instance_type     = "m5.large"
monitoring_capacity_type     = "SPOT"
monitoring_disk_size         = 50
monitoring_desired_capacity  = 2
monitoring_min_capacity      = 2
monitoring_max_capacity      = 4

ecr_repository_name = "locust-staging-load-tests"
ecr_scan_on_push    = true

log_retention_days = 30
