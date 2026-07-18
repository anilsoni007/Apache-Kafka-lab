import json
import asyncio
import logging
from datetime import datetime, timezone
from contextlib import asynccontextmanager

from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware
from aiokafka import AIOKafkaConsumer, AIOKafkaProducer
from aiokafka.errors import KafkaError

from config import settings
from fraud_engine import FraudEngine

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

fraud_engine = FraudEngine()
recent_alerts: list[dict] = []  # In-memory store for UI (use Redis in production)


def make_kafka_client_kwargs() -> dict:
    is_msk = settings.kafka_security_protocol == "SASL_SSL"
    kwargs = {"bootstrap_servers": settings.kafka_bootstrap_servers,
              "security_protocol": settings.kafka_security_protocol}
    if is_msk:
        kwargs.update({
            "sasl_mechanism": "OAUTHBEARER",
            "sasl_oauth_token_provider": settings.get_msk_token_provider(),
        })
    return kwargs


async def consume_payments(producer: AIOKafkaProducer):
    consumer = AIOKafkaConsumer(
        settings.payments_topic,
        **make_kafka_client_kwargs(),
        group_id="fraud-detection-service",
        value_deserializer=lambda v: json.loads(v.decode()),
        key_deserializer=lambda k: k.decode() if k else None,
        # Production consumer settings
        auto_offset_reset="earliest",
        enable_auto_commit=False,   # Manual commit - process-then-commit pattern
        max_poll_records=50,
        session_timeout_ms=30000,
        heartbeat_interval_ms=10000,
    )

    await consumer.start()
    logger.info(f"Consumer started, subscribed to '{settings.payments_topic}'")

    try:
        async for msg in consumer:
            payment = msg.value
            payment_id = payment.get("payment_id", "unknown")

            try:
                result = fraud_engine.analyze(payment)

                if result["is_fraud"]:
                    alert = {
                        "payment_id": payment_id,
                        "amount": payment["amount"],
                        "sender_account": payment["sender_account"],
                        "fraud_score": result["score"],
                        "reasons": result["reasons"],
                        "detected_at": datetime.now(timezone.utc).isoformat(),
                        "kafka_partition": msg.partition,
                        "kafka_offset": msg.offset,
                    }
                    await producer.send_and_wait(
                        topic=settings.fraud_alerts_topic,
                        key=payment_id,
                        value=json.dumps(alert).encode(),
                    )
                    recent_alerts.insert(0, alert)
                    if len(recent_alerts) > 100:
                        recent_alerts.pop()
                    logger.warning(f"FRAUD DETECTED: payment_id={payment_id} score={result['score']}")

                # Manual commit AFTER successful processing
                await consumer.commit()

            except Exception as e:
                logger.error(f"Processing failed for {payment_id}: {e}")
                # Send to DLQ with error context
                dlq_event = {
                    "original_event": payment,
                    "error": str(e),
                    "failed_at": datetime.now(timezone.utc).isoformat(),
                    "partition": msg.partition,
                    "offset": msg.offset,
                }
                await producer.send(
                    topic=settings.dlq_topic,
                    value=json.dumps(dlq_event).encode(),
                )
                await consumer.commit()  # Commit to avoid reprocessing poison pill

    finally:
        await consumer.stop()


@asynccontextmanager
async def lifespan(app: FastAPI):
    producer = AIOKafkaProducer(
        **make_kafka_client_kwargs(),
        acks="all",
        enable_idempotence=True,
    )
    await producer.start()

    task = asyncio.create_task(consume_payments(producer))
    logger.info("Fraud detection consumer started")

    yield

    task.cancel()
    try:
        await task
    except asyncio.CancelledError:
        pass
    await producer.stop()


app = FastAPI(title="Fraud Detection Service", lifespan=lifespan)

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_methods=["*"],
    allow_headers=["*"],
)


@app.get("/health")
async def health():
    return {"status": "ok", "service": "fraud-detection-service"}


@app.get("/alerts")
async def get_alerts(limit: int = 20):
    """Returns recent fraud alerts for the UI"""
    return {"alerts": recent_alerts[:limit], "total": len(recent_alerts)}


@app.get("/alerts/stats")
async def get_stats():
    if not recent_alerts:
        return {"total_alerts": 0, "avg_fraud_score": 0, "top_reasons": []}

    scores = [a["fraud_score"] for a in recent_alerts]
    all_reasons = [r for a in recent_alerts for r in a["reasons"]]
    reason_counts = {}
    for r in all_reasons:
        reason_counts[r] = reason_counts.get(r, 0) + 1

    return {
        "total_alerts": len(recent_alerts),
        "avg_fraud_score": round(sum(scores) / len(scores), 2),
        "top_reasons": sorted(reason_counts.items(), key=lambda x: -x[1])[:5],
    }
