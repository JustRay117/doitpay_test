output "cluster_name" {
  description = "Name of the EKS cluster."
  value       = aws_eks_cluster.this.name
}

output "cluster_endpoint" {
  description = "URL of the Kubernetes API. Reachable only from inside the VPC."
  value       = aws_eks_cluster.this.endpoint
}

output "cluster_security_group_id" {
  description = "Security group that EKS created for the cluster. Needed to allow access from a VPN or bastion."
  value       = aws_eks_cluster.this.vpc_config[0].cluster_security_group_id
}

output "node_role_arn" {
  description = "ARN of the IAM role used by the worker nodes."
  value       = aws_iam_role.node.arn
}
