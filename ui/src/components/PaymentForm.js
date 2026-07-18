import { useState } from 'react';

const MERCHANT_CATEGORIES = ['RETAIL', 'FOOD', 'TRAVEL', 'CRYPTO', 'GAMBLING', 'WIRE_TRANSFER', 'CASH_ADVANCE'];

const PRESETS = [
  { label: '✅ Normal ($50)', amount: 50, merchant_category: 'RETAIL' },
  { label: '⚠️ Large ($6000)', amount: 6000, merchant_category: 'RETAIL' },
  { label: '🚨 Crypto ($15000)', amount: 15000, merchant_category: 'CRYPTO' },
  { label: '🔄 Velocity Test', amount: 100, merchant_category: 'RETAIL', repeat: 6 },
];

export default function PaymentForm({ onSubmit }) {
  const [form, setForm] = useState({
    amount: 100,
    currency: 'USD',
    sender_account: 'ACC001234',
    receiver_account: 'ACC005678',
    merchant_id: 'MERCH001',
    merchant_category: 'RETAIL',
  });
  const [status, setStatus] = useState(null);
  const [loading, setLoading] = useState(false);

  const submit = async (overrides = {}, repeat = 1) => {
    setLoading(true);
    setStatus(null);
    try {
      const payload = { ...form, ...overrides };
      let last;
      for (let i = 0; i < repeat; i++) {
        last = await onSubmit(payload);
        if (repeat > 1) await new Promise(r => setTimeout(r, 200));
      }
      setStatus({ type: 'success', message: `✅ Published to Kafka! ID: ${last.payment_id.slice(0, 8)}...` });
    } catch (e) {
      setStatus({ type: 'error', message: `❌ ${e.message}` });
    } finally {
      setLoading(false);
    }
  };

  return (
    <div className="payment-form">
      <div className="presets">
        {PRESETS.map(p => (
          <button
            key={p.label}
            className="preset-btn"
            onClick={() => submit({ amount: p.amount, merchant_category: p.merchant_category }, p.repeat || 1)}
            disabled={loading}
          >
            {p.label}
          </button>
        ))}
      </div>

      <div className="form-grid">
        <label>
          Amount ($)
          <input type="number" value={form.amount} min="1"
            onChange={e => setForm(f => ({ ...f, amount: parseFloat(e.target.value) }))} />
        </label>
        <label>
          Merchant Category
          <select value={form.merchant_category}
            onChange={e => setForm(f => ({ ...f, merchant_category: e.target.value }))}>
            {MERCHANT_CATEGORIES.map(c => <option key={c}>{c}</option>)}
          </select>
        </label>
        <label>
          Sender Account
          <input value={form.sender_account}
            onChange={e => setForm(f => ({ ...f, sender_account: e.target.value }))} />
        </label>
        <label>
          Receiver Account
          <input value={form.receiver_account}
            onChange={e => setForm(f => ({ ...f, receiver_account: e.target.value }))} />
        </label>
      </div>

      <button className="submit-btn" onClick={() => submit()} disabled={loading}>
        {loading ? 'Publishing to Kafka...' : '🚀 Send Payment Event'}
      </button>

      {status && <div className={`status ${status.type}`}>{status.message}</div>}
    </div>
  );
}
