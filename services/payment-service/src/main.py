import uuid
import json
import logging
import ssl
from datetime import datetime, timezone
from contextlib import asynccontextmanager

from fastapi import FastAPI, HTTPException
from fastapi.middleware.cors import CORSMiddleware
from pydantic import BaseModel, Field
from aiokafka import AIOKafkaProducer
from aiokafka.errors import KafkaError

from config import settings

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

producer: AIOKafkaProducer | None = None


@asynccontextmanager
async def lifespan(app: FastAPI):
    global producer
    is_msk = settings.kafka_security_protocol == "SASL_SSL"
    producer = AIOKafkaProducer(
        bootstrap_servers=settings.kafka_bootstrap_servers,
        security_protocol=settings.kafka_security_protocol,
        **({
            "sasl_mechanism": "OAUTHBEARER",
            "sasl_oauth_token_provider": settings.get_msk_token_provider(),
            "ssl_context": ssl.create_default_context(),
        } if is_msk else {}),
        value_serializer=lambda v: json.dumps(v).encode(),
        key_serializer=lambda k: k.encode() if k else None,
        # Production settings
        acks="all",
        enable_idempotence=True,
        compression_type="gzip",
        linger_ms=5,
    )
    await producer.start()
    logger.info("Kafka producer started")
    yield
    await producer.stop()
    logger.info("Kafka producer stopped")


app = FastAPI(title="Payment Service", lifespan=lifespan)

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_methods=["*"],
    allow_headers=["*"],
)


class PaymentRequest(BaseModel):
    amount: float = Field(gt=0, description="Payment amount in USD")
    currency: str = Field(default="USD", max_length=3)
    sender_account: str = Field(min_length=5, max_length=20)
    receiver_account: str = Field(min_length=5, max_length=20)
    merchant_id: str
    merchant_category: str = Field(default="RETAIL")


class PaymentResponse(BaseModel):
    payment_id: str
    status: str
    timestamp: str


@app.post("/payments", response_model=PaymentResponse, status_code=202)
async def create_payment(req: PaymentRequest):
    """
    Accepts a payment and publishes it to the 'payments' Kafka topic.
    Returns 202 Accepted - processing is async via fraud-detection-service.
    """
    payment_id = str(uuid.uuid4())
    timestamp = datetime.now(timezone.utc).isoformat()

    event = {
        "payment_id": payment_id,
        "amount": req.amount,
        "currency": req.currency,
        "sender_account": req.sender_account,
        "receiver_account": req.receiver_account,
        "merchant_id": req.merchant_id,
        "merchant_category": req.merchant_category,
        "timestamp": timestamp,
        "schema_version": "1.0",
    }

    try:
        # Use sender_account as partition key - same sender always goes to same partition
        # This preserves ordering per sender (important for fraud detection)
        record_metadata = await producer.send_and_wait(
            topic=settings.payments_topic,
            key=req.sender_account,
            value=event,
        )
        logger.info(
            "Payment published",
            extra={
                "payment_id": payment_id,
                "partition": record_metadata.partition,
                "offset": record_metadata.offset,
            },
        )
    except KafkaError as e:
        logger.error(f"Failed to publish payment {payment_id}: {e}")
        raise HTTPException(status_code=503, detail="Payment processing unavailable")

    return PaymentResponse(payment_id=payment_id, status="PROCESSING", timestamp=timestamp)


@app.get("/health")
async def health():
    return {"status": "ok", "service": "payment-service"}


@app.get("/payments/topics/info")
async def topic_info():
    """Dev endpoint - shows Kafka topic metadata for learning"""
    if not producer:
        raise HTTPException(status_code=503, detail="Producer not ready")
    partitions = await producer.partitions_for(settings.payments_topic)
    return {
        "topic": settings.payments_topic,
        "partitions": list(partitions),
        "bootstrap_servers": settings.kafka_bootstrap_servers,
    }
