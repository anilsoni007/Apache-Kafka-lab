# Kafka Fintech Lab — EKS + MSK Event-Driven Architecture

A production-grade learning lab simulating a fintech payment fraud detection system.

## Architecture

```
┌─────────────┐     POST /payments      ┌──────────────────┐
│   React UI  │ ──────────────────────► │  payment-service │
│  (port 3000)│                         │  (FastAPI/Python) │
└─────────────┘                         └────────┬─────────┘
       ▲                                         │ produce
       │ GET /alerts (poll 3s)                   ▼
       │                               ┌─────────────────────┐
       │                               │   MSK (Kafka)        │
       │                               │   topic: payments    │
       │                               │   6 partitions       │
       │                               └──────────┬──────────┘
       │                                          │ consume
       │                               ┌──────────▼──────────┐
       │                               │ fraud-detection-svc  │
       └───────────────────────────────│  (FastAPI/Python)    │
         fraud-alerts topic            └──────────┬──────────┘
                                                  │ produce
                                       ┌──────────▼──────────┐
                                       │  topic: fraud-alerts │
                                       │  topic: payments.DLQ │
                                       └─────────────────────┘
```

## Key Kafka Concepts You'll Learn

| Concept | Where it's used |
|---|---|
| **Partitioning** | payments topic has 6 partitions; sender_account is the key → ordering per sender |
| **Consumer Groups** | fraud-detection-service group; 2 replicas = 2 consumers = parallel processing |
| **Manual Commit** | Process-then-commit pattern in fraud service (no message loss) |
| **DLQ Pattern** | Failed messages go to payments.DLQ for investigation |
| **Idempotent Producer** | `enable_idempotence=True` prevents duplicate messages on retry |
| **IAM Auth (IRSA)** | Pods use AWS IAM roles — no passwords, auto-rotating credentials |
| **Replication Factor 3** | Each message stored on 3 brokers; survives 1 broker failure |
| **min.insync.replicas=2** | Producer waits for 2 replicas to ack before confirming write |

## Project Structure

```
├── infra/                    # Terraform (VPC + EKS + MSK)
│   └── modules/
│       ├── vpc/              # Multi-AZ VPC with NAT gateways
│       ├── eks/              # EKS cluster + IRSA roles
│       └── msk/              # MSK cluster + config
├── services/
│   ├── payment-service/      # Kafka producer (FastAPI)
│   └── fraud-detection-service/  # Kafka consumer + producer (FastAPI)
├── helm/                     # Kubernetes manifests (Helm)
├── ui/                       # React dashboard
├── scripts/deploy.sh         # End-to-end deploy script
└── docker-compose.yml        # Local dev (no AWS needed)
```

---

## Option A — Local Quick Start (No AWS needed)

### Prerequisites
- Docker + Docker Compose
- Node.js >= 18 (for the UI)

### Step 1 — Start Kafka + services

```bash
docker-compose up -d
```

Expected: 5 containers running + 1 exited (kafka-init is a one-shot topic creator)

```bash
docker ps
# payment-service      → port 8000
# fraud-detection-svc  → port 8001
# kafka-ui             → port 8080
# kafka                → port 9092
# zookeeper
```

### Step 2 — Start the React UI

```bash
cd ui
npm install
npm start
# Opens http://localhost:3000
```

### Step 3 — Open Kafka UI

```
http://localhost:8080
```

Use this to observe topics, partitions, offsets, and consumer group lag in real time.

---

## Option B — Deploy to AWS (EKS + MSK)

### Prerequisites

- AWS CLI configured (`aws configure`)
- Terraform >= 1.5
- kubectl
- helm
- docker
- An EC2 instance or machine with network access to EKS (to run kubectl commands)

### Step 1 — Configure Terraform variables

```bash
cp infra/terraform.tfvars.example infra/terraform.tfvars
```

Edit `infra/terraform.tfvars`:

```hcl
aws_region   = "us-east-1"
project_name = "kafka-lab"
environment  = "dev"

# sandbox → kafka.t3.small, 3 brokers, 10GB EBS, t3.small nodes (~$5/day)
# production → kafka.m5.large, 3 brokers, 100GB EBS, t3.medium nodes (~$13/day)
env_profile = "sandbox"

kafka_version = "3.7.x"
k8s_version   = "1.31"
```

### Step 2 — Provision infrastructure with Terraform

```bash
cd infra
terraform init
terraform apply -auto-approve
```

This takes ~20 minutes (MSK provisioning is slow). When complete you will see:

```
eks_cluster_name          = "kafka-lab-dev"
eks_cluster_endpoint      = "https://..."
msk_bootstrap_brokers_iam = <sensitive>
payment_service_role_arn  = "arn:aws:iam::..."
fraud_service_role_arn    = "arn:aws:iam::..."
```

To view sensitive outputs:

```bash
terraform output -raw msk_bootstrap_brokers_iam
```

### Step 3 — Configure kubectl

```bash
aws eks update-kubeconfig --region us-east-1 --name kafka-lab-dev

# Verify nodes are ready
kubectl get nodes
```

### Step 4 — Create Kafka namespace and topics

```bash
kubectl create namespace kafka-lab --dry-run=client -o yaml | kubectl apply -f -

# Create the client config for MSK IAM auth
kubectl create configmap kafka-client-config \
  --namespace kafka-lab \
  --from-literal=client.properties="security.protocol=SASL_SSL
sasl.mechanism=AWS_MSK_IAM
sasl.jaas.config=software.amazon.msk.auth.iam.IAMLoginModule required;
sasl.client.callback.handler.class=software.amazon.msk.auth.iam.IAMClientCallbackHandler" \
  --dry-run=client -o yaml | kubectl apply -f -
```

Set your MSK brokers variable:

```bash
MSK_BROKERS=$(cd infra && terraform output -raw msk_bootstrap_brokers_iam)
```

Create topics via a Kubernetes Job (runs inside the cluster where MSK is reachable):

```bash
cat <<EOF | kubectl apply -f -
apiVersion: batch/v1
kind: Job
metadata:
  name: kafka-topic-init
  namespace: kafka-lab
spec:
  ttlSecondsAfterFinished: 300
  template:
    spec:
      restartPolicy: OnFailure
      containers:
        - name: kafka-init
          image: confluentinc/cp-kafka:7.6.0
          command: ["/bin/sh", "-c"]
          args:
            - |
              kafka-topics --bootstrap-server ${MSK_BROKERS} \
                --command-config /tmp/client.properties \
                --create --if-not-exists --topic payments \
                --partitions 6 --replication-factor 3 --config retention.ms=604800000
              kafka-topics --bootstrap-server ${MSK_BROKERS} \
                --command-config /tmp/client.properties \
                --create --if-not-exists --topic fraud-alerts \
                --partitions 3 --replication-factor 3 --config retention.ms=2592000000
              kafka-topics --bootstrap-server ${MSK_BROKERS} \
                --command-config /tmp/client.properties \
                --create --if-not-exists --topic payments.DLQ \
                --partitions 3 --replication-factor 3 --config retention.ms=2592000000
              echo "Topics created successfully"
          volumeMounts:
            - name: client-config
              mountPath: /tmp/client.properties
              subPath: client.properties
      volumes:
        - name: client-config
          configMap:
            name: kafka-client-config
EOF

kubectl wait --for=condition=complete job/kafka-topic-init -n kafka-lab --timeout=120s
```

### Step 5 — Build and push Docker images to ECR

```bash
AWS_REGION="us-east-1"
AWS_ACCOUNT=$(aws sts get-caller-identity --query Account --output text)
ECR_REGISTRY="${AWS_ACCOUNT}.dkr.ecr.${AWS_REGION}.amazonaws.com"

# Login to ECR
aws ecr get-login-password --region $AWS_REGION | \
  docker login --username AWS --password-stdin $ECR_REGISTRY

# Run from the repo root (where services/ folder is)
cd ~/Apache-Kafka-lab

# Create repos and push images
for svc in payment-service fraud-detection-service; do
  aws ecr describe-repositories --repository-names $svc --region $AWS_REGION 2>/dev/null || \
    aws ecr create-repository --repository-name $svc --region $AWS_REGION
  docker build -t $ECR_REGISTRY/$svc:latest services/$svc/
  docker push $ECR_REGISTRY/$svc:latest
done
```

### Step 6 — Deploy services with Helm

```bash
PAYMENT_ROLE=$(cd infra && terraform output -raw payment_service_role_arn)
FRAUD_ROLE=$(cd infra && terraform output -raw fraud_service_role_arn)

# MSK brokers contain commas so pass via a values file to avoid --set parsing issues
cat > /tmp/brokers.yaml <<EOF
kafka:
  bootstrapServers: "${MSK_BROKERS}"
EOF

helm upgrade --install payment-service helm/payment-service \
  --namespace kafka-lab \
  -f /tmp/brokers.yaml \
  --set image.repository="$ECR_REGISTRY/payment-service" \
  --set serviceAccount.annotations."eks\.amazonaws\.com/role-arn"="$PAYMENT_ROLE"

helm upgrade --install fraud-detection-service helm/fraud-detection-service \
  --namespace kafka-lab \
  -f /tmp/brokers.yaml \
  --set image.repository="$ECR_REGISTRY/fraud-detection-service" \
  --set serviceAccount.annotations."eks\.amazonaws\.com/role-arn"="$FRAUD_ROLE"
```

### Step 7 — Verify pods are running

```bash
kubectl rollout status deployment/payment-service -n kafka-lab
kubectl rollout status deployment/fraud-detection-service -n kafka-lab

kubectl get pods -n kafka-lab
```

### Step 8 — Access services

```bash
# Port-forward to test locally
kubectl port-forward svc/payment-service 8000:80 -n kafka-lab &
kubectl port-forward svc/fraud-detection-service 8001:80 -n kafka-lab &

# Health checks
curl http://localhost:8000/health
curl http://localhost:8001/health
```

### Step 9 — Start the UI

```bash
cd ui
npm install
REACT_APP_PAYMENT_API=http://localhost:8000 \
REACT_APP_FRAUD_API=http://localhost:8001 \
npm start
# Opens http://localhost:3000
```

---

## Fraud Detection Test Scenarios

| Scenario | How to trigger | Expected result |
|---|---|---|
| Normal payment | Amount $50, RETAIL | No alert |
| Large amount | Amount > $10,000 | Alert: HIGH_AMOUNT |
| High-risk merchant | Category: CRYPTO/GAMBLING | Alert: HIGH_RISK_CATEGORY |
| Velocity attack | Click "Velocity Test" (6 rapid txns) | Alert: VELOCITY |
| Combined fraud | $15,000 + CRYPTO | Score ~0.7, multiple reasons |

---

## Validating the End-to-End Flow

### Step 1 — Submit a payment via React UI
Open `http://localhost:3000`, fill in the payment form and submit. The UI polls `GET /alerts` every 3 seconds and displays fraud alerts automatically.

### Step 2 — Observe Kafka message flow (Kafka UI)
Open `http://localhost:8080` (local) and check:
- **Topics → payments** — confirm the message landed with a partition number and offset
- **Topics → fraud-alerts** — confirm the fraud alert was produced (for fraud scenarios)
- **Consumer Groups → fraud-detection-service** — lag should be `0`, meaning all messages were processed

### Step 3 — Validate via APIs

```bash
# View recent fraud alerts
curl http://localhost:8001/alerts

# View fraud stats (total alerts, avg score, top reasons)
curl http://localhost:8001/alerts/stats

# Check payment service health
curl http://localhost:8000/health

# Check topic partition metadata
curl http://localhost:8000/payments/topics/info
```

### Step 4 — Prove key-based partitioning

Submit multiple payments with the same `sender_account` (default: `ACC001234`), then check logs:

```bash
# Local
docker logs apache-kafka-lab-payment-service-1 2>&1 | grep "Payment published"

# EKS
kubectl logs -f deploy/payment-service -n kafka-lab
```

Same `sender_account` always lands on the same partition. Change `sender_account` to `ACC009999` and it will land on a different partition — this proves key-based partitioning.

### Step 5 — Observe fraud detection processing

```bash
# Local
docker logs apache-kafka-lab-fraud-detection-service-1 -f

# EKS
kubectl logs -f deploy/fraud-detection-service -n kafka-lab
```

### What to look for

| Observation | Kafka concept it proves |
|---|---|
| Same sender_account → same partition every time | Key-based partitioning |
| Consumer group lag = 0 after processing | Manual commit working correctly |
| Fraud alert appears in `fraud-alerts` topic | Producer chaining (consumer → producer) |
| Failed message appears in `payments.DLQ` | DLQ pattern |
| No duplicate messages on retry | Idempotent producer |

---

## Useful kubectl Commands (EKS)

```bash
# Watch pods
kubectl get pods -n kafka-lab -w

# Check consumer group lag
kubectl exec -it deploy/fraud-detection-service -n kafka-lab -- \
  kafka-consumer-groups.sh --bootstrap-server $MSK_BROKERS \
  --describe --group fraud-detection-service

# View logs
kubectl logs -f deploy/payment-service -n kafka-lab
kubectl logs -f deploy/fraud-detection-service -n kafka-lab

# Scale consumers (max = number of partitions = 6)
kubectl scale deploy/fraud-detection-service --replicas=4 -n kafka-lab
```

---

## Cost Estimate (AWS)

| Profile | MSK | EKS nodes | NAT GWs | ~Cost/day |
|---|---|---|---|---|
| **sandbox** | 3x kafka.t3.small | 1x t3.small | 3x | ~$8 |
| **production** | 3x kafka.m5.large | 2x t3.medium | 3x | ~$13 |

> Destroy when not in use: `cd infra && terraform destroy`
