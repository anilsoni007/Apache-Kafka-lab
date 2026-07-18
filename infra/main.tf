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
  broker_instance    = var.msk_broker_instance
  broker_count       = var.msk_broker_count
  environment        = var.environment
}

module "eks" {
  source          = "./modules/eks"
  name            = "${var.project_name}-${var.environment}"
  vpc_id          = module.vpc.vpc_id
  subnet_ids      = module.vpc.private_subnet_ids
  k8s_version     = var.k8s_version
  node_instance   = var.eks_node_instance
  min_nodes       = var.eks_min_nodes
  max_nodes       = var.eks_max_nodes
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
