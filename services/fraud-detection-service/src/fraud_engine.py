from dataclasses import dataclass, field
from collections import defaultdict, deque
from datetime import datetime, timezone
import time


@dataclass
class FraudResult:
    is_fraud: bool
    score: float
    reasons: list[str]


class FraudEngine:
    """
    Rule-based fraud detection engine.
    In production: replace/augment with ML model (SageMaker endpoint).
    
    Scoring: 0.0 (clean) → 1.0 (definite fraud). Threshold: 0.6
    """
    FRAUD_THRESHOLD = 0.6

    # Track per-sender: recent amounts and timestamps (sliding window)
    _sender_history: dict[str, deque] = defaultdict(lambda: deque(maxlen=20))

    def analyze(self, payment: dict) -> dict:
        score = 0.0
        reasons = []

        amount = payment["amount"]
        sender = payment["sender_account"]
        category = payment.get("merchant_category", "RETAIL")
        now = time.time()

        # Rule 1: Large single transaction
        if amount > 10000:
            score += 0.4
            reasons.append(f"HIGH_AMOUNT: ${amount:,.2f}")
        elif amount > 5000:
            score += 0.2
            reasons.append(f"ELEVATED_AMOUNT: ${amount:,.2f}")

        # Rule 2: High-risk merchant category
        high_risk_categories = {"CRYPTO", "GAMBLING", "WIRE_TRANSFER", "CASH_ADVANCE"}
        if category in high_risk_categories:
            score += 0.3
            reasons.append(f"HIGH_RISK_CATEGORY: {category}")

        # Rule 3: Velocity check - too many transactions in 60 seconds
        history = self._sender_history[sender]
        recent_txns = [t for t in history if now - t["ts"] < 60]
        if len(recent_txns) >= 5:
            score += 0.5
            reasons.append(f"VELOCITY: {len(recent_txns)} txns in 60s")
        elif len(recent_txns) >= 3:
            score += 0.2
            reasons.append(f"ELEVATED_VELOCITY: {len(recent_txns)} txns in 60s")

        # Rule 4: Rapid amount escalation
        if len(recent_txns) >= 2:
            prev_amounts = [t["amount"] for t in recent_txns[-3:]]
            if amount > max(prev_amounts) * 3:
                score += 0.3
                reasons.append("AMOUNT_SPIKE: 3x previous transactions")

        # Record this transaction
        history.append({"ts": now, "amount": amount})

        score = min(score, 1.0)
        return {
            "is_fraud": score >= self.FRAUD_THRESHOLD,
            "score": round(score, 2),
            "reasons": reasons,
        }
