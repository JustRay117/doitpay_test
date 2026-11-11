provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Project      = "paytrack"
      Environtment = var.environment
      ManagedBy    = "terraform"
    }
  }
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
