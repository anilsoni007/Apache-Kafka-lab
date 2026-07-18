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

## Quick Start — Local (No AWS needed)

```bash
# Start Kafka + both services
docker-compose up -d

# Start the UI
cd ui && npm install && npm start

# Open http://localhost:3000
# Open http://localhost:8080 for Kafka UI (see topics, consumer groups, offsets)
```

## Deploy to AWS (EKS + MSK)

### Prerequisites
- AWS CLI configured (`aws configure`)
- Terraform >= 1.5
- kubectl, helm, docker

```bash
# 1. Copy and edit vars
cp infra/terraform.tfvars.example infra/terraform.tfvars

# 2. Full deploy (takes ~20 min for MSK to provision)
chmod +x scripts/deploy.sh
./scripts/deploy.sh

# 3. Port-forward to test
kubectl port-forward svc/payment-service 8000:80 -n kafka-lab &
kubectl port-forward svc/fraud-detection-service 8001:80 -n kafka-lab &

# 4. Start UI pointing to EKS services
cd ui
REACT_APP_PAYMENT_API=http://localhost:8000 \
REACT_APP_FRAUD_API=http://localhost:8001 \
npm start
```

## Fraud Detection Test Scenarios

| Scenario | How to trigger | Expected result |
|---|---|---|
| Normal payment | Amount $50, RETAIL | No alert |
| Large amount | Amount > $10,000 | Alert: HIGH_AMOUNT |
| High-risk merchant | Category: CRYPTO/GAMBLING | Alert: HIGH_RISK_CATEGORY |
| Velocity attack | Click "Velocity Test" (6 rapid txns) | Alert: VELOCITY |
| Combined fraud | $15,000 + CRYPTO | Score ~0.7, multiple reasons |

## Useful kubectl Commands

```bash
# Watch pods
kubectl get pods -n kafka-lab -w

# Check consumer group lag (key metric in production)
kubectl exec -it deploy/fraud-detection-service -n kafka-lab -- \
  kafka-consumer-groups.sh --bootstrap-server $MSK_BROKERS \
  --describe --group fraud-detection-service

# View payment-service logs (see partition + offset per message)
kubectl logs -f deploy/payment-service -n kafka-lab

# Scale consumers (max = number of partitions = 6)
kubectl scale deploy/fraud-detection-service --replicas=4 -n kafka-lab
```

## Cost Estimate (AWS)

| Resource | Type | ~Cost/day |
|---|---|---|
| MSK | 3x kafka.t3.small | ~$5 |
| EKS cluster | Control plane | ~$2.40 |
| EKS nodes | 2x t3.medium | ~$2 |
| NAT Gateways | 3x | ~$3.60 |
| **Total** | | **~$13/day** |

> Destroy when not in use: `cd infra && terraform destroy`

## Project Structure

```
├── infra/                    # Terraform (VPC + EKS + MSK)
│   └── modules/
│       ├── vpc/              # Multi-AZ VPC with NAT gateways
│       ├── eks/              # EKS cluster + IRSA roles
│       └── msk/              # MSK cluster + topics + config
├── services/
│   ├── payment-service/      # Kafka producer (FastAPI)
│   └── fraud-detection-service/  # Kafka consumer + producer (FastAPI)
├── helm/                     # Kubernetes manifests (Helm)
├── ui/                       # React dashboard
├── scripts/deploy.sh         # End-to-end deploy script
└── docker-compose.yml        # Local dev (no AWS needed)
```
