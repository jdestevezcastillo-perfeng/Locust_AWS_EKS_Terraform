################################################################################
# General Variables
################################################################################

variable "aws_region" {
  description = "AWS region where resources will be created"
  type        = string
  default     = "eu-central-1"
}

variable "environment" {
  description = "Environment name (dev, staging, prod)"
  type        = string
  default     = "dev"
}

################################################################################
# VPC and Networking Variables
################################################################################

variable "vpc_cidr" {
  description = "CIDR block for VPC"
  type        = string
  default     = "10.0.0.0/16"
}

variable "public_subnet_cidrs" {
  description = "CIDR blocks for public subnets"
  type        = list(string)
  default     = ["10.0.1.0/24", "10.0.2.0/24"]
}

variable "private_subnet_cidrs" {
  description = "CIDR blocks for private subnets"
  type        = list(string)
  default     = ["10.0.10.0/24", "10.0.20.0/24"]
}

################################################################################
# EKS Cluster Variables
################################################################################

variable "cluster_name" {
  description = "Name of the EKS cluster"
  type        = string
  default     = "locust-cluster"
}

variable "kubernetes_version" {
  description = "Kubernetes version for EKS cluster"
  type        = string
  default     = "1.28"
}

variable "cluster_endpoint_public_access" {
  description = "Enable public access to cluster endpoint"
  type        = bool
  default     = true
}

variable "cluster_endpoint_public_access_cidrs" {
  description = "List of CIDR blocks that can access the cluster endpoint (use ['0.0.0.0/0'] for testing, restrict in production)"
  type        = list(string)
  default     = ["0.0.0.0/0"]
}

################################################################################
# EKS Node Group Variables
################################################################################

variable "node_group_name" {
  description = "Name of the EKS node group"
  type        = string
  default     = "locust-nodes"
}

variable "node_instance_type" {
  description = "EC2 instance type for worker nodes"
  type        = string
  default     = "t3.medium"

  validation {
    condition     = can(regex("^t3\\.(nano|micro|small|medium|large|xlarge|2xlarge)$", var.node_instance_type))
    error_message = "Node instance type must be a valid t3 instance (t3.nano, t3.micro, t3.small, t3.medium, t3.large, t3.xlarge, t3.2xlarge)."
  }
}

variable "node_capacity_type" {
  description = "Type of capacity associated with the EKS Node Group. Valid values: ON_DEMAND, SPOT"
  type        = string
  default     = "SPOT"

  validation {
    condition     = contains(["ON_DEMAND", "SPOT"], var.node_capacity_type)
    error_message = "Node capacity type must be either ON_DEMAND or SPOT."
  }
}

variable "node_disk_size" {
  description = "Disk size in GB for worker nodes"
  type        = number
  default     = 20
}

variable "desired_capacity" {
  description = "Desired number of worker nodes"
  type        = number
  default     = 3

  validation {
    condition     = var.desired_capacity >= 1 && var.desired_capacity <= 100
    error_message = "Desired capacity must be between 1 and 100."
  }
}

variable "min_capacity" {
  description = "Minimum number of worker nodes"
  type        = number
  default     = 3

  validation {
    condition     = var.min_capacity >= 1 && var.min_capacity <= 100
    error_message = "Minimum capacity must be between 1 and 100."
  }
}

variable "max_capacity" {
  description = "Maximum number of worker nodes"
  type        = number
  default     = 10

  validation {
    condition     = var.max_capacity >= 1 && var.max_capacity <= 100
    error_message = "Maximum capacity must be between 1 and 100."
  }
}

################################################################################
# ECR Variables
################################################################################

variable "ecr_repository_name" {
  description = "Name of the ECR repository for Locust images"
  type        = string
  default     = "locust-load-tests"
}

variable "ecr_scan_on_push" {
  description = "Enable vulnerability scanning on image push"
  type        = bool
  default     = false
}

################################################################################
# CloudWatch Logging Variables
################################################################################

variable "log_retention_days" {
  description = "Number of days to retain CloudWatch logs"
  type        = number
  default     = 7

  validation {
    condition     = contains([1, 3, 5, 7, 14, 30, 60, 90, 120, 150, 180, 365, 400, 545, 731, 1827, 3653], var.log_retention_days)
    error_message = "Log retention days must be a valid CloudWatch Logs retention period."
  }
}
