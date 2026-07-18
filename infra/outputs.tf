output "eks_cluster_name" {
  description = "EKS cluster name for kubectl config"
  value       = module.eks.cluster_name
}

output "eks_cluster_endpoint" {
  description = "EKS API endpoint"
  value       = module.eks.cluster_endpoint
}

output "msk_bootstrap_brokers_iam" {
  description = "MSK bootstrap brokers (IAM auth) - use this in your services"
  value       = module.msk.bootstrap_brokers_iam
  sensitive   = true
}

output "msk_bootstrap_brokers_tls" {
  description = "MSK bootstrap brokers (TLS)"
  value       = module.msk.bootstrap_brokers_tls
  sensitive   = true
}

output "msk_zookeeper_connect" {
  description = "MSK Zookeeper connection string"
  value       = module.msk.zookeeper_connect
  sensitive   = true
}

output "payment_service_role_arn" {
  description = "IAM role ARN for payment-service pod (IRSA)"
  value       = module.eks.payment_service_role_arn
}

output "fraud_service_role_arn" {
  description = "IAM role ARN for fraud-detection-service pod (IRSA)"
  value       = module.eks.fraud_service_role_arn
}

output "kubeconfig_command" {
  description = "Run this to configure kubectl"
  value       = "aws eks update-kubeconfig --region ${var.aws_region} --name ${module.eks.cluster_name}"
}
