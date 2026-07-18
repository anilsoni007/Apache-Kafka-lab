export default function KafkaStats({ stats }) {
  if (!stats) return <div className="kafka-stats loading">Loading Kafka stats...</div>;

  return (
    <div className="kafka-stats">
      <h3>📊 Kafka Pipeline Stats</h3>
      <div className="stats-grid">
        <div className="stat">
          <div className="stat-value">{stats.total_alerts}</div>
          <div className="stat-label">Fraud Alerts</div>
        </div>
        <div className="stat">
          <div className="stat-value">{(stats.avg_fraud_score * 100).toFixed(0)}%</div>
          <div className="stat-label">Avg Fraud Score</div>
        </div>
      </div>

      {stats.top_reasons?.length > 0 && (
        <div className="top-reasons">
          <strong>Top Fraud Signals:</strong>
          {stats.top_reasons.map(([reason, count]) => (
            <div key={reason} className="reason-row">
              <span>{reason}</span>
              <span className="count">{count}x</span>
            </div>
          ))}
        </div>
      )}

      <div className="architecture-note">
        <strong>Flow:</strong> UI → payment-service → MSK (payments topic) → fraud-detection-service → MSK (fraud-alerts topic) → UI
      </div>
    </div>
  );
}
