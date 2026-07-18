#!/bin/bash
# deploy.sh - Full deployment script for Kafka Lab
# Prerequisites: aws cli, terraform, kubectl, helm, docker

set -euo pipefail

AWS_REGION="${AWS_REGION:-us-east-1}"
AWS_ACCOUNT=$(aws sts get-caller-identity --query Account --output text)
ECR_REGISTRY="${AWS_ACCOUNT}.dkr.ecr.${AWS_REGION}.amazonaws.com"

echo "=== Step 1: Terraform - Provision EKS + MSK ==="
cd infra
cp terraform.tfvars.example terraform.tfvars
terraform init
terraform apply -auto-approve
MSK_BROKERS=$(terraform output -raw msk_bootstrap_brokers_iam)
EKS_CLUSTER=$(terraform output -raw eks_cluster_name)
PAYMENT_ROLE=$(terraform output -raw payment_service_role_arn)
FRAUD_ROLE=$(terraform output -raw fraud_service_role_arn)
cd ..

echo "=== Step 2: Configure kubectl ==="
aws eks update-kubeconfig --region "$AWS_REGION" --name "$EKS_CLUSTER"
kubectl create namespace kafka-lab --dry-run=client -o yaml | kubectl apply -f -

echo "=== Step 3: Build & Push Docker images to ECR ==="
aws ecr get-login-password --region "$AWS_REGION" | \
  docker login --username AWS --password-stdin "$ECR_REGISTRY"

for svc in payment-service fraud-detection-service; do
  aws ecr describe-repositories --repository-names "$svc" --region "$AWS_REGION" 2>/dev/null || \
    aws ecr create-repository --repository-name "$svc" --region "$AWS_REGION"

  docker build -t "$ECR_REGISTRY/$svc:latest" "services/$svc/"
  docker push "$ECR_REGISTRY/$svc:latest"
done

echo "=== Step 4: Deploy with Helm ==="
helm upgrade --install payment-service helm/payment-service \
  --namespace kafka-lab \
  --set image.repository="$ECR_REGISTRY/payment-service" \
  --set kafka.bootstrapServers="$MSK_BROKERS" \
  --set serviceAccount.annotations."eks\.amazonaws\.com/role-arn"="$PAYMENT_ROLE"

helm upgrade --install fraud-detection-service helm/fraud-detection-service \
  --namespace kafka-lab \
  --set image.repository="$ECR_REGISTRY/fraud-detection-service" \
  --set kafka.bootstrapServers="$MSK_BROKERS" \
  --set serviceAccount.annotations."eks\.amazonaws\.com/role-arn"="$FRAUD_ROLE"

echo "=== Step 5: Wait for pods ==="
kubectl rollout status deployment/payment-service -n kafka-lab
kubectl rollout status deployment/fraud-detection-service -n kafka-lab

echo ""
echo "✅ Deployment complete!"
echo ""
echo "To access services locally:"
echo "  kubectl port-forward svc/payment-service 8000:80 -n kafka-lab"
echo "  kubectl port-forward svc/fraud-detection-service 8001:80 -n kafka-lab"
echo ""
echo "Then start the UI:"
echo "  cd ui && npm install && npm start"
