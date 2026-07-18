# Security group - only allow EKS nodes to reach MSK
resource "aws_security_group" "msk" {
  name        = "${var.name}-msk-sg"
  description = "MSK cluster security group"
  vpc_id      = var.vpc_id

  ingress {
    description     = "Kafka IAM/TLS from EKS nodes"
    from_port       = 9098
    to_port         = 9098
    protocol        = "tcp"
    security_groups = var.allowed_sg_ids
  }

  ingress {
    description     = "Kafka TLS from EKS nodes"
    from_port       = 9094
    to_port         = 9094
    protocol        = "tcp"
    security_groups = var.allowed_sg_ids
  }

  ingress {
    description     = "Zookeeper from EKS nodes"
    from_port       = 2181
    to_port         = 2181
    protocol        = "tcp"
    security_groups = var.allowed_sg_ids
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "${var.name}-msk-sg" }
}

resource "aws_msk_configuration" "this" {
  name              = "${var.name}-config"
  kafka_versions    = [var.kafka_version]
  # Production-grade Kafka configuration
  server_properties = <<-EOF
    auto.create.topics.enable=false
    default.replication.factor=3
    min.insync.replicas=2
    num.partitions=6
    log.retention.hours=168
    log.segment.bytes=1073741824
    log.retention.check.interval.ms=300000
    num.recovery.threads.per.data.dir=1
    offsets.topic.replication.factor=3
    transaction.state.log.replication.factor=3
    transaction.state.log.min.isr=2
    group.initial.rebalance.delay.ms=3000
  EOF
}

resource "aws_msk_cluster" "this" {
  cluster_name           = var.name
  kafka_version          = var.kafka_version
  number_of_broker_nodes = var.broker_count

  broker_node_group_info {
    instance_type   = var.broker_instance
    client_subnets  = var.subnet_ids
    security_groups = [aws_security_group.msk.id]

    storage_info {
      ebs_storage_info {
        volume_size = 100 # GB per broker
      }
    }
  }

  configuration_info {
    arn      = aws_msk_configuration.this.arn
    revision = aws_msk_configuration.this.latest_revision
  }

  # IAM auth - production best practice (no passwords to manage)
  client_authentication {
    sasl {
      iam = true
    }
    tls {}
  }

  encryption_info {
    encryption_in_transit {
      client_broker = "TLS"
      in_cluster    = true
    }
  }

  # Enable enhanced monitoring for CloudWatch metrics
  enhanced_monitoring = "PER_TOPIC_PER_BROKER"

  open_monitoring {
    prometheus {
      jmx_exporter  { enabled_in_broker = true }
      node_exporter { enabled_in_broker = true }
    }
  }

  logging_info {
    broker_logs {
      cloudwatch_logs {
        enabled   = true
        log_group = aws_cloudwatch_log_group.msk.name
      }
    }
  }

  tags = { Name = var.name }
}

resource "aws_cloudwatch_log_group" "msk" {
  name              = "/aws/msk/${var.name}"
  retention_in_days = 7
}

# Kafka topics - created via Terraform for GitOps
resource "aws_msk_topic" "payments" {
  cluster_arn        = aws_msk_cluster.this.arn
  topic_name         = "payments"
  partitions         = 6  # Allows 6 parallel consumers
  replication_factor = 3
  config = {
    "retention.ms"    = "604800000" # 7 days
    "cleanup.policy"  = "delete"
  }
}

resource "aws_msk_topic" "fraud_alerts" {
  cluster_arn        = aws_msk_cluster.this.arn
  topic_name         = "fraud-alerts"
  partitions         = 3
  replication_factor = 3
  config = {
    "retention.ms"   = "2592000000" # 30 days - fraud data kept longer
    "cleanup.policy" = "delete"
  }
}

resource "aws_msk_topic" "payments_dlq" {
  cluster_arn        = aws_msk_cluster.this.arn
  topic_name         = "payments.DLQ"
  partitions         = 3
  replication_factor = 3
  config = {
    "retention.ms"   = "2592000000" # 30 days for investigation
    "cleanup.policy" = "delete"
  }
}
