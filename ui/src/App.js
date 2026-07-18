import { useState, useEffect, useCallback } from 'react';
import PaymentForm from './components/PaymentForm';
import FraudAlerts from './components/FraudAlerts';
import KafkaStats from './components/KafkaStats';
import './App.css';

const PAYMENT_API = process.env.REACT_APP_PAYMENT_API || 'http://localhost:8000';
const FRAUD_API = process.env.REACT_APP_FRAUD_API || 'http://localhost:8001';

export default function App() {
  const [alerts, setAlerts] = useState([]);
  const [stats, setStats] = useState(null);
  const [recentPayments, setRecentPayments] = useState([]);

  const fetchAlerts = useCallback(async () => {
    try {
      const [alertsRes, statsRes] = await Promise.all([
        fetch(`${FRAUD_API}/alerts?limit=20`),
        fetch(`${FRAUD_API}/alerts/stats`),
      ]);
      setAlerts((await alertsRes.json()).alerts);
      setStats(await statsRes.json());
    } catch (e) {
      console.error('Failed to fetch alerts:', e);
    }
  }, []);

  // Poll for new fraud alerts every 3 seconds
  useEffect(() => {
    fetchAlerts();
    const interval = setInterval(fetchAlerts, 3000);
    return () => clearInterval(interval);
  }, [fetchAlerts]);

  const handlePaymentSubmit = async (payment) => {
    const res = await fetch(`${PAYMENT_API}/payments`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify(payment),
    });
    if (!res.ok) throw new Error(`HTTP ${res.status}`);
    const data = await res.json();
    setRecentPayments(prev => [{ ...payment, ...data }, ...prev].slice(0, 10));
    return data;
  };

  return (
    <div className="app">
      <header>
        <h1>🏦 Kafka Fintech Lab</h1>
        <p>EKS + MSK Event-Driven Architecture Demo</p>
      </header>

      <div className="grid">
        <section>
          <h2>Submit Payment</h2>
          <PaymentForm onSubmit={handlePaymentSubmit} />
          <RecentPayments payments={recentPayments} />
        </section>

        <section>
          <KafkaStats stats={stats} />
          <FraudAlerts alerts={alerts} />
        </section>
      </div>
    </div>
  );
}

function RecentPayments({ payments }) {
  if (!payments.length) return null;
  return (
    <div className="recent-payments">
      <h3>Recent Payments (Kafka Events)</h3>
      {payments.map(p => (
        <div key={p.payment_id} className="payment-row">
          <span className="status processing">⏳ PROCESSING</span>
          <span>${p.amount.toLocaleString()}</span>
          <span className="id">{p.payment_id?.slice(0, 8)}...</span>
        </div>
      ))}
    </div>
  );
}
