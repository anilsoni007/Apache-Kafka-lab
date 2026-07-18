export default function FraudAlerts({ alerts }) {
  return (
    <div className="fraud-alerts">
      <h3>🚨 Fraud Alerts (Live from Kafka)</h3>
      {alerts.length === 0 ? (
        <p className="empty">No fraud detected yet. Try the preset buttons!</p>
      ) : (
        <div className="alerts-list">
          {alerts.map(alert => (
            <div key={alert.payment_id} className="alert-card">
              <div className="alert-header">
                <span className="score" style={{ color: scoreColor(alert.fraud_score) }}>
                  Score: {(alert.fraud_score * 100).toFixed(0)}%
                </span>
                <span className="amount">${alert.amount?.toLocaleString()}</span>
                <span className="time">{new Date(alert.detected_at).toLocaleTimeString()}</span>
              </div>
              <div className="alert-meta">
                <span>Account: {alert.sender_account}</span>
                <span className="kafka-info">
                  partition={alert.kafka_partition} offset={alert.kafka_offset}
                </span>
              </div>
              <div className="reasons">
                {alert.reasons?.map(r => <span key={r} className="reason-tag">{r}</span>)}
              </div>
            </div>
          ))}
        </div>
      )}
    </div>
  );
}

function scoreColor(score) {
  if (score >= 0.8) return '#ef4444';
  if (score >= 0.6) return '#f97316';
  return '#eab308';
}
