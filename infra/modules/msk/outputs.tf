output "cluster_arn"            { value = aws_msk_cluster.this.arn }
output "bootstrap_brokers_iam"  { value = aws_msk_cluster.this.bootstrap_brokers_sasl_iam }
output "bootstrap_brokers_tls"  { value = aws_msk_cluster.this.bootstrap_brokers_tls }
output "zookeeper_connect"      { value = aws_msk_cluster.this.zookeeper_connect_string }
output "security_group_id"      { value = aws_security_group.msk.id }
