################################################################################
# VPC Outputs
################################################################################

output "vpc_id" {
  description = "ID of the VPC"
  value       = aws_vpc.eks_vpc.id
}

output "vpc_cidr" {
  description = "CIDR block of the VPC"
  value       = aws_vpc.eks_vpc.cidr_block
}

output "public_subnet_ids" {
  description = "IDs of public subnets"
  value       = [aws_subnet.public_subnet_1.id, aws_subnet.public_subnet_2.id]
}

output "private_subnet_ids" {
  description = "IDs of private subnets"
  value       = [aws_subnet.private_subnet_1.id, aws_subnet.private_subnet_2.id]
}

output "nat_gateway_ips" {
  description = "Elastic IPs of NAT Gateways"
  value       = [aws_eip.nat_eip_1.public_ip, aws_eip.nat_eip_2.public_ip]
}

################################################################################
# EKS Cluster Outputs
################################################################################

output "cluster_id" {
  description = "EKS cluster ID"
  value       = aws_eks_cluster.main.id
}

output "cluster_name" {
  description = "EKS cluster name"
  value       = aws_eks_cluster.main.name
}

output "cluster_endpoint" {
  description = "Endpoint for EKS control plane"
  value       = aws_eks_cluster.main.endpoint
}

output "cluster_arn" {
  description = "ARN of the EKS cluster"
  value       = aws_eks_cluster.main.arn
}

output "cluster_version" {
  description = "Kubernetes version of the cluster"
  value       = aws_eks_cluster.main.version
}

output "cluster_security_group_id" {
  description = "Security group ID attached to the EKS cluster"
  value       = aws_security_group.eks_cluster_sg.id
}

output "cluster_certificate_authority_data" {
  description = "Base64 encoded certificate data required to communicate with the cluster"
  value       = aws_eks_cluster.main.certificate_authority[0].data
  sensitive   = true
}

################################################################################
# EKS Node Group Outputs
################################################################################

output "node_group_id" {
  description = "EKS node group ID"
  value       = aws_eks_node_group.main.id
}

output "node_group_arn" {
  description = "ARN of the EKS node group"
  value       = aws_eks_node_group.main.arn
}

output "node_group_status" {
  description = "Status of the EKS node group"
  value       = aws_eks_node_group.main.status
}

output "node_security_group_id" {
  description = "Security group ID attached to the EKS nodes"
  value       = aws_security_group.eks_nodes_sg.id
}

output "node_instance_role_arn" {
  description = "IAM role ARN for EKS node group"
  value       = aws_iam_role.eks_node_group_role.arn
}

################################################################################
# ECR Outputs
################################################################################

output "ecr_repository_url" {
  description = "URL of the ECR repository"
  value       = aws_ecr_repository.locust.repository_url
}

output "ecr_repository_arn" {
  description = "ARN of the ECR repository"
  value       = aws_ecr_repository.locust.arn
}

output "ecr_repository_name" {
  description = "Name of the ECR repository"
  value       = aws_ecr_repository.locust.name
}

################################################################################
# CloudWatch Outputs
################################################################################

output "cluster_log_group_name" {
  description = "CloudWatch log group name for EKS cluster logs"
  value       = aws_cloudwatch_log_group.eks_cluster_logs.name
}

output "container_log_group_name" {
  description = "CloudWatch log group name for container logs"
  value       = aws_cloudwatch_log_group.eks_container_logs.name
}

output "cluster_log_group_arn" {
  description = "ARN of the CloudWatch log group for cluster logs"
  value       = aws_cloudwatch_log_group.eks_cluster_logs.arn
}

################################################################################
# Utility Outputs
################################################################################

output "aws_region" {
  description = "AWS region"
  value       = var.aws_region
}

output "kubectl_config_command" {
  description = "Command to configure kubectl"
  value       = "aws eks update-kubeconfig --region ${var.aws_region} --name ${aws_eks_cluster.main.name}"
}

output "ecr_login_command" {
  description = "Command to authenticate Docker to ECR"
  value       = "aws ecr get-login-password --region ${var.aws_region} | docker login --username AWS --password-stdin ${aws_ecr_repository.locust.repository_url}"
  sensitive   = true
}

################################################################################
# Cost Estimation Outputs
################################################################################

output "estimated_monthly_cost" {
  description = "Estimated monthly cost breakdown (24/7 operation)"
  value = {
    eks_control_plane = "$73/month (fixed)"
    worker_nodes      = "$${var.desired_capacity * 30}/month (t3.medium at ~$30/node)"
    nat_gateways      = "$65/month (2 NAT Gateways)"
    cloudwatch_logs   = "$5-15/month (variable)"
    total_estimate    = "$${143 + (var.desired_capacity * 30)}/month"
    note              = "DESTROY resources when not in use to minimize costs!"
  }
}
