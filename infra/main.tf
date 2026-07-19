terraform {
  required_version = ">= 1.5"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.0"
    }
    helm = {
      source  = "hashicorp/helm"
      version = "~> 2.0"
    }
  }
  # Uncomment for remote state (recommended for production)
  # backend "s3" {
  #   bucket = "your-terraform-state-bucket"
  #   key    = "kafka-lab/terraform.tfstate"
  #   region = "us-east-1"
  # }
}

locals {
  profiles = {
    sandbox = {
      msk_broker_instance  = "kafka.t3.small"
      msk_broker_count     = 3          # must match AZ count (3 AZs = 3 brokers min)
      msk_ebs_volume_size  = 10         # GB - minimal storage
      msk_monitoring       = "DEFAULT"  # no enhanced monitoring cost
      eks_node_instance    = "t3.small"
      eks_min_nodes        = 1
      eks_max_nodes        = 2
    }
    production = {
      msk_broker_instance  = "kafka.m5.large"
      msk_broker_count     = 3
      msk_ebs_volume_size  = 100
      msk_monitoring       = "PER_TOPIC_PER_BROKER"
      eks_node_instance    = "t3.medium"
      eks_min_nodes        = 2
      eks_max_nodes        = 4
    }
  }

  profile = local.profiles[var.env_profile]

  # Allow explicit var overrides, otherwise use profile defaults
  msk_broker_instance = var.msk_broker_instance != "" ? var.msk_broker_instance : local.profile.msk_broker_instance
  msk_broker_count    = var.msk_broker_count != 0 ? var.msk_broker_count : local.profile.msk_broker_count
}

provider "aws" {
  region = var.aws_region
  default_tags {
    tags = {
      Project     = "kafka-lab"
      Environment = var.environment
      ManagedBy   = "terraform"
    }
  }
}

module "vpc" {
  source      = "./modules/vpc"
  name        = "${var.project_name}-${var.environment}"
  cidr        = var.vpc_cidr
  azs         = var.availability_zones
  environment = var.environment
}

module "msk" {
  source             = "./modules/msk"
  name               = "${var.project_name}-${var.environment}"
  vpc_id             = module.vpc.vpc_id
  subnet_ids         = module.vpc.private_subnet_ids
  allowed_sg_ids     = [module.eks.node_security_group_id]
  kafka_version      = var.kafka_version
  broker_instance    = local.msk_broker_instance
  broker_count       = local.msk_broker_count
  ebs_volume_size    = local.profile.msk_ebs_volume_size
  monitoring_level   = local.profile.msk_monitoring
  environment        = var.environment
}

module "eks" {
  source          = "./modules/eks"
  name            = "${var.project_name}-${var.environment}"
  vpc_id          = module.vpc.vpc_id
  subnet_ids      = module.vpc.private_subnet_ids
  k8s_version     = var.k8s_version
  node_instance   = local.profile.eks_node_instance
  min_nodes       = local.profile.eks_min_nodes
  max_nodes       = local.profile.eks_max_nodes
  msk_cluster_arn = module.msk.cluster_arn
  environment     = var.environment
}

provider "kubernetes" {
  host                   = module.eks.cluster_endpoint
  cluster_ca_certificate = base64decode(module.eks.cluster_ca)
  exec {
    api_version = "client.authentication.k8s.io/v1beta1"
    command     = "aws"
    args        = ["eks", "get-token", "--cluster-name", module.eks.cluster_name]
  }
}

provider "helm" {
  kubernetes {
    host                   = module.eks.cluster_endpoint
    cluster_ca_certificate = base64decode(module.eks.cluster_ca)
    exec {
      api_version = "client.authentication.k8s.io/v1beta1"
      command     = "aws"
      args        = ["eks", "get-token", "--cluster-name", module.eks.cluster_name]
    }
  }
}
