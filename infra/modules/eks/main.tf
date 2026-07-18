data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

# ─── EKS Cluster ────────────────────────────────────────────────────────────

resource "aws_iam_role" "cluster" {
  name = "${var.name}-eks-cluster-role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "eks.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy_attachment" "cluster_policy" {
  role       = aws_iam_role.cluster.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSClusterPolicy"
}

resource "aws_eks_cluster" "this" {
  name     = var.name
  version  = var.k8s_version
  role_arn = aws_iam_role.cluster.arn

  vpc_config {
    subnet_ids              = var.subnet_ids
    endpoint_private_access = true
    endpoint_public_access  = true # Set false in production, use VPN/bastion
  }

  enabled_cluster_log_types = ["api", "audit", "authenticator"]

  depends_on = [aws_iam_role_policy_attachment.cluster_policy]
}

# OIDC provider - required for IRSA (IAM Roles for Service Accounts)
data "tls_certificate" "eks" {
  url = aws_eks_cluster.this.identity[0].oidc[0].issuer
}

resource "aws_iam_openid_connect_provider" "eks" {
  client_id_list  = ["sts.amazonaws.com"]
  thumbprint_list = [data.tls_certificate.eks.certificates[0].sha1_fingerprint]
  url             = aws_eks_cluster.this.identity[0].oidc[0].issuer
}

# ─── Node Group ─────────────────────────────────────────────────────────────

resource "aws_iam_role" "nodes" {
  name = "${var.name}-eks-node-role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "ec2.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy_attachment" "nodes" {
  for_each = toset([
    "arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy",
    "arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy",
    "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly",
  ])
  role       = aws_iam_role.nodes.name
  policy_arn = each.value
}

resource "aws_eks_node_group" "this" {
  cluster_name    = aws_eks_cluster.this.name
  node_group_name = "${var.name}-nodes"
  node_role_arn   = aws_iam_role.nodes.arn
  subnet_ids      = var.subnet_ids
  instance_types  = [var.node_instance]

  scaling_config {
    desired_size = var.min_nodes
    min_size     = var.min_nodes
    max_size     = var.max_nodes
  }

  update_config { max_unavailable = 1 }

  depends_on = [aws_iam_role_policy_attachment.nodes]
}

# Get node security group for MSK ingress rules
data "aws_security_group" "node" {
  filter {
    name   = "tag:aws:eks:cluster-name"
    values = [aws_eks_cluster.this.name]
  }
  filter {
    name   = "tag:kubernetes.io/cluster/${aws_eks_cluster.this.name}"
    values = ["owned"]
  }
  depends_on = [aws_eks_node_group.this]
}

# ─── IRSA: payment-service ───────────────────────────────────────────────────

resource "aws_iam_role" "payment_service" {
  name = "${var.name}-payment-service"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = {
        Federated = aws_iam_openid_connect_provider.eks.arn
      }
      Action = "sts:AssumeRoleWithWebIdentity"
      Condition = {
        StringEquals = {
          "${replace(aws_iam_openid_connect_provider.eks.url, "https://", "")}:sub" = "system:serviceaccount:kafka-lab:payment-service"
          "${replace(aws_iam_openid_connect_provider.eks.url, "https://", "")}:aud" = "sts.amazonaws.com"
        }
      }
    }]
  })
}

resource "aws_iam_policy" "payment_service_msk" {
  name = "${var.name}-payment-service-msk"
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = ["kafka-cluster:Connect", "kafka-cluster:DescribeCluster"]
        Resource = var.msk_cluster_arn
      },
      {
        Effect = "Allow"
        Action = [
          "kafka-cluster:ReadData",
          "kafka-cluster:WriteData",
          "kafka-cluster:DescribeTopic",
          "kafka-cluster:CreateTopic"
        ]
        Resource = "${var.msk_cluster_arn}/topic/payments*"
      },
      {
        Effect   = "Allow"
        Action   = ["kafka-cluster:AlterGroup", "kafka-cluster:DescribeGroup"]
        Resource = "${var.msk_cluster_arn}/group/payment-service*"
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "payment_service_msk" {
  role       = aws_iam_role.payment_service.name
  policy_arn = aws_iam_policy.payment_service_msk.arn
}

# ─── IRSA: fraud-detection-service ──────────────────────────────────────────

resource "aws_iam_role" "fraud_service" {
  name = "${var.name}-fraud-service"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = {
        Federated = aws_iam_openid_connect_provider.eks.arn
      }
      Action = "sts:AssumeRoleWithWebIdentity"
      Condition = {
        StringEquals = {
          "${replace(aws_iam_openid_connect_provider.eks.url, "https://", "")}:sub" = "system:serviceaccount:kafka-lab:fraud-detection-service"
          "${replace(aws_iam_openid_connect_provider.eks.url, "https://", "")}:aud" = "sts.amazonaws.com"
        }
      }
    }]
  })
}

resource "aws_iam_policy" "fraud_service_msk" {
  name = "${var.name}-fraud-service-msk"
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = ["kafka-cluster:Connect", "kafka-cluster:DescribeCluster"]
        Resource = var.msk_cluster_arn
      },
      {
        Effect = "Allow"
        Action = ["kafka-cluster:ReadData", "kafka-cluster:DescribeTopic"]
        Resource = "${var.msk_cluster_arn}/topic/payments"
      },
      {
        Effect = "Allow"
        Action = [
          "kafka-cluster:WriteData",
          "kafka-cluster:DescribeTopic",
          "kafka-cluster:CreateTopic"
        ]
        Resource = "${var.msk_cluster_arn}/topic/fraud-alerts"
      },
      {
        Effect = "Allow"
        Action = [
          "kafka-cluster:WriteData",
          "kafka-cluster:DescribeTopic"
        ]
        Resource = "${var.msk_cluster_arn}/topic/payments.DLQ"
      },
      {
        Effect   = "Allow"
        Action   = ["kafka-cluster:AlterGroup", "kafka-cluster:DescribeGroup"]
        Resource = "${var.msk_cluster_arn}/group/fraud-detection*"
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "fraud_service_msk" {
  role       = aws_iam_role.fraud_service.name
  policy_arn = aws_iam_policy.fraud_service_msk.arn
}
