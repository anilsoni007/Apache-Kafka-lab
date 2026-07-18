variable "aws_region" {
  description = "AWS region"
  type        = string
  default     = "us-east-1"
}

variable "project_name" {
  description = "Project name used for resource naming"
  type        = string
  default     = "kafka-lab"
}

variable "environment" {
  description = "Environment name"
  type        = string
  default     = "dev"
}

variable "vpc_cidr" {
  description = "VPC CIDR block"
  type        = string
  default     = "10.0.0.0/16"
}

variable "availability_zones" {
  description = "List of AZs (min 2 for MSK)"
  type        = list(string)
  default     = ["us-east-1a", "us-east-1b", "us-east-1c"]
}

# MSK
variable "kafka_version" {
  description = "Apache Kafka version"
  type        = string
  default     = "3.5.1"
}

variable "msk_broker_instance" {
  description = "MSK broker instance type"
  type        = string
  default     = "kafka.t3.small" # Use kafka.m5.large for production
}

variable "msk_broker_count" {
  description = "Number of brokers (must be multiple of AZ count)"
  type        = number
  default     = 3
}

# EKS
variable "k8s_version" {
  description = "Kubernetes version"
  type        = string
  default     = "1.29"
}

variable "eks_node_instance" {
  description = "EKS node instance type"
  type        = string
  default     = "t3.medium"
}

variable "eks_min_nodes" {
  type    = number
  default = 2
}

variable "eks_max_nodes" {
  type    = number
  default = 4
}
