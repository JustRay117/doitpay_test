provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Project      = "paytrack"
      Environtment = var.environment
      ManagedBy    = "terraform"
    }
  }
  skip_credentials_validation = true
  skip_requesting_account_id  = true
  skip_metadata_api_check     = true
}

# IAM role for EKS control plane
resource "aws_iam_role" "cluster" {
  name = "${var.cluster_name}-cluster-role"

  # Trust policy to allow EKS service to use this role.
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect    = "Allow"
        Principal = { Service = "eks.amazonaws.com" }
        Action    = "sts:AssumeRole"
      }
    ]
  })
}

# Permissions for EKS cluster
resource "aws_iam_role_policy_attachment" "cluster_policy" {
  role       = aws_iam_role.cluster.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSClusterPolicy"
}

# EKS Cluster

resource "aws_eks_cluster" "this" {
  name     = var.cluster_name
  version  = var.kubernetes_version
  role_arn = aws_iam_role.cluster.arn

  # Networking is using existing private subnets
  # PayTrack is internal use only
  vpc_config {
    subnet_ids              = var.private_subnet_ids
    endpoint_private_access = true
    endpoint_public_access  = false
  }

  # Access to cluster thru EKS (IAM Based)
  access_config {
    authentication_mode = "API"
  }

  # Role Permissions for EKS to create cluster
  depends_on = [aws_iam_role_policy_attachment.cluster_policy]
}

# Worker nodes IAM roles

# Roles for EC2 instances
resource "aws_iam_role" "node" {
  name = "${var.cluster_name}-node-role"

  # Trust policy for EC2 instance role
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect    = "Allow"
        Principal = { Service = "ec2.amazonaws.com" }
        Action    = "sts:AssumeRole"
      }
    ]
  })
}

# Allow node register to cluster
resource "aws_iam_role_policy_attachment" "node_worker_policy" {
  role       = aws_iam_role.node.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy"
}

# Allow node to only pull container images from ECR
resource "aws_iam_role_policy_attachment" "node_ecr_pull_policy" {
  role       = aws_iam_role.node.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryPullOnly"
}

# Allow VPC CNI plugin to give pods an IP Address from subnets
resource "aws_iam_role_policy_attachment" "node_cni_policy" {
  role       = aws_iam_role.node.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy"
}

# Managed node group (worker nodes)
resource "aws_eks_node_group" "this" {
  cluster_name    = aws_eks_cluster.this.name
  node_group_name = "${var.cluster_name}-nodes"
  node_role_arn   = aws_iam_role.node.arn

  # Nodes in existing private subnets doesn't have public IP address
  subnet_ids     = var.private_subnet_ids
  instance_types = var.node_instance_types

  scaling_config {
    desired_size = var.desired_size
    min_size     = var.min_size
    max_size     = var.max_size
  }

  # The role policies before nodes can join the cluster.
  depends_on = [
    aws_iam_role_policy_attachment.node_worker_policy,
    aws_iam_role_policy_attachment.node_ecr_pull_policy,
    aws_iam_role_policy_attachment.node_cni_policy,
  ]
}
