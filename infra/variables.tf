variable "aws_region" {
  description = "AWS region for EKS cluster"
  type        = string
}

variable "environment" {
  description = "Environtment tags"
  type        = string
}

variable "cluster_name" {
  description = "EKS cluster name"
  type        = string
}

variable "kubernetes_version" {
  description = "Kube version"
  type        = string
}

variable "private_subnet_ids" {
  description = "ID of existing Private Subnets, at least 2 for EKS in different AZ"
  type        = list(string)
}

variable "node_instance_types" {
  description = "EC2 instance types for the worker nodes."
  type        = list(string)
}

variable "desired_size" {
  description = "Desired number of worker nodes"
}

variable "min_size" {
  description = "Minimum number of worker nodes."
  type        = number
}

variable "max_size" {
  description = "Maximum number of worker nodes"
  type        = number
}
