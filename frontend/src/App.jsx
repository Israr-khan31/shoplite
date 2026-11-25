import { useCallback, useEffect, useState } from 'react';
import { api } from './api.js';
const SERVICES = ['catalog', 'inventory', 'orders'];
const rs = (n) => 'Rs ' + Number(n || 0).toLocaleString();
function Status() {
  const [st, setSt] = useState({});
  useEffect(() => {
    const check = () => SERVICES.forEach((s) => api.health(s).then((b) => setSt((p) => ({ ...p, [s]: b.status === 'ok' }))).catch(() => setSt((p) => ({ ...p, [s]: false }))));
    check();
    const t = setInterval(check, 5000);
    return () => clearInterval(t);
  }, []);
  return (
    <div className="card row">
      <div><b>System status</b><div className="sub">Live connection to your microservices</div></div>
      <div className="dots">{SERVICES.map((s) => <span key={s} className={st[s] === undefined ? '' : st[s] ? 'up' : 'down'}>{s}</span>)}</div>
    </div>
  );
}
function Stock({ products }) {
  return (
    <div className="card">
      <div className="row"><b>Product inventory</b><span className="pill">{products.length} products</span></div>
      <table>
        <thead><tr><th>ID</th><th>Name</th><th>Price</th><th>In stock</th></tr></thead>
        <tbody>{products.map((p) => <tr key={p.id}><td>{p.id}</td><td>{p.name}</td><td>{rs(p.price)}</td><td className={p.stock <= 5 ? 'low' : ''}>{p.stock ?? '-'}</td></tr>)}</tbody>
      </table>
    </div>
  );
}
function OrderForm({ products, onOrdered }) {
  const [pid, setPid] = useState('');
  const [qty, setQty] = useState(1);
  const [msg, setMsg] = useState('');
  const submit = async (e) => {
    e.preventDefault();
    try {
      const o = await api.createOrder(Number(pid || products[0]?.id), Number(qty));
      setMsg('Order #' + o.id + ' placed, total ' + rs(o.total));
      onOrdered();
    } catch (err) {
      setMsg('Failed: ' + err.message);
    }
  };
  return (
    <div className="card">
      <b>New order</b>
      <form onSubmit={submit}>
        <select value={pid} onChange={(e) => setPid(e.target.value)}>{products.map((p) => <option key={p.id} value={p.id}>{p.name}</option>)}</select>
        <input type="number" min="1" value={qty} onChange={(e) => setQty(e.target.value)} />
        <button className="btn" type="submit" disabled={products.length === 0}>Order</button>
      </form>
      {msg && <p>{msg}</p>}
    </div>
  );
}
function OrderList({ orders }) {
  return (
    <div className="card">
      <div className="row"><b>Orders</b><span className="pill">{orders.length} orders</span></div>
      {orders.length === 0 ? <p className="sub">No orders yet.</p> : (
        <table>
          <thead><tr><th>ID</th><th>Product</th><th>Qty</th><th>Total</th><th>Created</th></tr></thead>
          <tbody>{orders.map((o) => <tr key={o.id}><td>{o.id}</td><td>{o.productId}</td><td>{o.quantity}</td><td>{rs(o.total)}</td><td>{new Date(o.createdAt).toLocaleString()}</td></tr>)}</tbody>
        </table>
      )}
    </div>
  );
}
export default function App() {
  const [products, setProducts] = useState([]);
  const [orders, setOrders] = useState([]);
  const [error, setError] = useState('');
  const [page, setPage] = useState('overview');
  const load = useCallback(async () => {
    try {
      const list = await api.products();
      const withStock = await Promise.all(list.map((p) => api.stock(p.id).then((s) => ({ ...p, stock: s.quantity })).catch(() => p)));
      setProducts(withStock);
      setOrders(await api.orders().catch(() => []));
      setError('');
    } catch (err) {
      setError('Could not load products: ' + err.message);
    }
  }, []);
  useEffect(() => { load(); }, [load]);
  const low = products.filter((p) => p.stock <= 5).length;
  const value = products.reduce((a, p) => a + (p.price || 0) * (p.stock || 0), 0);
  const titles = { overview: 'Overview', products: 'Products', orders: 'Orders' };
  return (
    <div className="app">
      <aside className="side">
        <div className="brand"><div className="logo">S</div><div><b>ShopLite</b><div className="sub">Management</div></div></div>
        {Object.keys(titles).map((k) => <button key={k} className={'nav' + (page === k ? ' on' : '')} onClick={() => setPage(k)}>{titles[k]}</button>)}
      </aside>
      <div className="main">
        <div className="top">
          <div><div className="sub">Workspace / {titles[page]}</div><h1>{titles[page]}</h1><div className="sub">Here is what is happening with your store today.</div></div>
          <button className="btn" onClick={() => setPage('orders')}>+ New order</button>
        </div>
        <div className="content">
          {error && <p className="error">{error}</p>}
          <Status />
          {page === 'overview' && (<>
            <div className="row"><b>Store overview</b><button className="btn light" onClick={load}>Refresh data</button></div>
            <div className="stats">
              <div className="card stat"><small>Total products</small><b>{products.length}</b></div>
              <div className="card stat"><small>Total orders</small><b>{orders.length}</b></div>
              <div className="card stat"><small>Low stock items</small><b>{low}</b></div>
              <div className="card stat"><small>Inventory value</small><b>{rs(value)}</b></div>
            </div>
            <Stock products={products} />
          </>)}
          {page === 'products' && <Stock products={products} />}
          {page === 'orders' && (<><OrderForm products={products} onOrdered={load} /><OrderList orders={orders} /></>)}
        </div>
      </div>
    </div>
  );
}
