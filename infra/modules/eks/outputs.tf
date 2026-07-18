output "cluster_name"              { value = aws_eks_cluster.this.name }
output "cluster_endpoint"          { value = aws_eks_cluster.this.endpoint }
output "cluster_ca"                { value = aws_eks_cluster.this.certificate_authority[0].data }
output "node_security_group_id"    { value = data.aws_security_group.node.id }
output "oidc_provider_arn"         { value = aws_iam_openid_connect_provider.eks.arn }
output "payment_service_role_arn"  { value = aws_iam_role.payment_service.arn }
output "fraud_service_role_arn"    { value = aws_iam_role.fraud_service.arn }
