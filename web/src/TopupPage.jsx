import { useState, useEffect, useRef, useCallback } from 'react'

const API_BASE = import.meta.env.VITE_API_BASE_URL || 'https://shopho-production.up.railway.app/api/v1'

const PACKAGE_META = {
  5:   { highlight: false, badge: null,            perSlotFn: (p) => `${(p/5).toLocaleString('vi-VN')} ₫ / lượt` },
  20:  { highlight: true,  badge: 'Phổ biến',      perSlotFn: (p) => `${(p/20).toLocaleString('vi-VN')} ₫ / lượt` },
  100: { highlight: false, badge: 'Tiết kiệm nhất',perSlotFn: (p) => `${(p/100).toLocaleString('vi-VN')} ₫ / lượt` },
}

function formatVnd(n) {
  return n.toLocaleString('vi-VN') + ' ₫'
}

// ── Step 1: Package selection ────────────────────────────────

function PackageStep({ token, onOrderCreated }) {
  const [packages, setPackages] = useState([])
  const [loading, setLoading] = useState(false)
  const [error, setError] = useState(null)

  useEffect(() => {
    fetch(`${API_BASE}/slots/topup/packages`)
      .then(r => r.json())
      .then(data => {
        const pkgs = data.map(({ slots, price_vnd }) => ({
          slots,
          price: price_vnd,
          priceLabel: price_vnd.toLocaleString('vi-VN') + ' ₫',
          perSlot: PACKAGE_META[slots]?.perSlotFn(price_vnd) ?? '',
          highlight: PACKAGE_META[slots]?.highlight ?? false,
          badge: PACKAGE_META[slots]?.badge ?? null,
        }))
        setPackages(pkgs)
      })
      .catch(() => setError('Không tải được danh sách gói. Vui lòng thử lại.'))
  }, [])

  async function handleSelect(pkg) {
    if (!token) {
      setError('Không tìm thấy token xác thực. Vui lòng mở lại từ ứng dụng ShopHo.')
      return
    }
    setLoading(true)
    setError(null)
    try {
      const res = await fetch(`${API_BASE}/users/me/slots/topup/create`, {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          Authorization: `Bearer ${token}`,
        },
        body: JSON.stringify({ slots_amount: pkg.slots }),
      })
      const data = await res.json()
      if (!res.ok) throw new Error(data.detail || 'Không thể tạo đơn nạp lượt')
      onOrderCreated({ ...data, slots_amount: pkg.slots })
    } catch (e) {
      setError(e.message)
    } finally {
      setLoading(false)
    }
  }

  return (
    <div style={styles.container}>
      <div style={styles.header}>
        <div style={styles.logo}>
          <svg width="24" height="24" viewBox="0 0 24 24" fill="none">
            <rect width="24" height="24" rx="6" fill="#5B6AF0"/>
            <path d="M7 12h10M12 7l5 5-5 5" stroke="#fff" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round"/>
          </svg>
          <span style={styles.logoText}>ShopHo</span>
        </div>
        <h1 style={styles.title}>Nạp lượt</h1>
        <p style={styles.subtitle}>Chọn gói lượt phù hợp để tiếp tục tạo và nhận đơn</p>
      </div>

      <div style={styles.packageList}>
        {packages.length === 0 && !error && <div style={{ textAlign: 'center', color: '#888', padding: 24 }}>Đang tải...</div>}
        {packages.map((pkg) => (
          <button
            key={pkg.slots}
            style={{
              ...styles.packageCard,
              ...(pkg.highlight ? styles.packageCardHighlight : {}),
            }}
            onClick={() => !loading && handleSelect(pkg)}
            disabled={loading}
          >
            {pkg.badge && (
              <span style={{
                ...styles.badge,
                background: pkg.highlight ? '#5B6AF0' : '#34a853',
              }}>
                {pkg.badge}
              </span>
            )}
            <div style={styles.packageTop}>
              <div style={styles.slotCount}>
                <span style={{
                  ...styles.slotNumber,
                  color: pkg.highlight ? '#5B6AF0' : '#1a1a2e',
                }}>
                  {pkg.slots}
                </span>
                <span style={styles.slotLabel}>lượt</span>
              </div>
              <div style={styles.priceBlock}>
                <span style={styles.price}>{pkg.priceLabel}</span>
                <span style={styles.perSlot}>{pkg.perSlot}</span>
              </div>
            </div>
            <div style={styles.packageDesc}>
              Tạo đơn hoặc nhận đơn · {pkg.slots} lần
            </div>
          </button>
        ))}
      </div>

      {error && <div style={styles.errorBox}>{error}</div>}

      {loading && (
        <div style={styles.loadingOverlay}>
          <div style={styles.spinner} />
          <p style={{ color: '#666', marginTop: 12 }}>Đang tạo đơn...</p>
        </div>
      )}
    </div>
  )
}

// ── Step 2: QR code + polling ─────────────────────────────────

function QRStep({ token, order, onSuccess, onBack }) {
  const [status, setStatus] = useState('pending')
  const [error, setError] = useState(null)
  const intervalRef = useRef(null)

  useEffect(() => {
    intervalRef.current = setInterval(async () => {
      try {
        const res = await fetch(
          `${API_BASE}/users/me/slots/topup/${order.order_code}`,
          { headers: { Authorization: `Bearer ${token}` } }
        )
        const data = await res.json()
        if (data.status === 'completed') {
          clearInterval(intervalRef.current)
          setStatus('completed')
          onSuccess(data)
        }
      } catch {
        // ignore transient errors
      }
    }, 3000)

    return () => clearInterval(intervalRef.current)
  }, [order.order_code, token, onSuccess])

  function copyCode() {
    navigator.clipboard.writeText(order.order_code).catch(() => {})
  }

  return (
    <div style={styles.container}>
      <button style={styles.backBtn} onClick={onBack}>
        <svg width="18" height="18" viewBox="0 0 24 24" fill="none">
          <path d="M15 18l-6-6 6-6" stroke="currentColor" strokeWidth="2.2" strokeLinecap="round" strokeLinejoin="round"/>
        </svg>
        Quay lại
      </button>
      <div style={styles.header}>
        <div style={styles.logo}>
          <svg width="24" height="24" viewBox="0 0 24 24" fill="none">
            <rect width="24" height="24" rx="6" fill="#5B6AF0"/>
            <path d="M7 12h10M12 7l5 5-5 5" stroke="#fff" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round"/>
          </svg>
          <span style={styles.logoText}>ShopHo</span>
        </div>
        <h1 style={styles.title}>Quét mã thanh toán</h1>
      </div>

      <div style={styles.qrCard}>
        <div style={styles.qrInfo}>
          <span style={styles.qrInfoLabel}>Gói đã chọn</span>
          <span style={styles.qrInfoValue}>{order.slots_amount} lượt · {formatVnd(order.amount_vnd)}</span>
        </div>

        <div style={styles.qrImageWrap}>
          <img
            src={order.qr_url}
            alt="QR thanh toán"
            style={styles.qrImage}
            onError={(e) => { e.target.style.display = 'none'; setError('Không tải được mã QR') }}
          />
        </div>

        {error && <div style={styles.errorBox}>{error}</div>}

        <div style={styles.bankInfo}>
          <div style={styles.bankRow}>
            <span style={styles.bankLabel}>Ngân hàng</span>
            <span style={styles.bankValue}>{order.bank_id}</span>
          </div>
          <div style={styles.bankRow}>
            <span style={styles.bankLabel}>Số tài khoản</span>
            <span style={styles.bankValue}>{order.account_number}</span>
          </div>
          <div style={styles.bankRow}>
            <span style={styles.bankLabel}>Số tiền</span>
            <span style={{ ...styles.bankValue, color: '#5B6AF0', fontWeight: 700 }}>
              {formatVnd(order.amount_vnd)}
            </span>
          </div>
          <div style={styles.bankRow}>
            <span style={styles.bankLabel}>Nội dung CK</span>
            <div style={styles.codeRow}>
              <span style={styles.orderCode}>{order.order_code}</span>
              <button style={styles.copyBtn} onClick={copyCode}>Sao chép</button>
            </div>
          </div>
        </div>

        <div style={styles.waitingRow}>
          <div style={styles.spinnerSmall} />
          <span style={{ color: '#666', fontSize: 13 }}>
            Đang chờ xác nhận thanh toán...
          </span>
        </div>

        <p style={styles.note}>
          Nhập <strong>đúng nội dung chuyển khoản</strong> để hệ thống tự động xác nhận.
          Lượt sẽ được cộng ngay sau khi nhận được tiền.
        </p>
      </div>
    </div>
  )
}

// ── Step 3: Success ───────────────────────────────────────────

function SuccessStep({ slots }) {
  useEffect(() => {
    const timer = setTimeout(() => {
      window.location.href = 'shopho://topup-success'
    }, 2000)
    return () => clearTimeout(timer)
  }, [])

  return (
    <div style={styles.container}>
      <div style={styles.successCard}>
        <div style={styles.successIcon}>✓</div>
        <h2 style={styles.successTitle}>Nạp lượt thành công!</h2>
        <p style={styles.successMsg}>
          <strong>{slots} lượt</strong> đã được cộng vào tài khoản của bạn.
        </p>
        <p style={styles.successHint}>Đang chuyển về ứng dụng ShopHo...</p>
        <button
          style={styles.backToAppBtn}
          onClick={() => { window.location.href = 'shopho://topup-success' }}
        >
          Quay lại ứng dụng
        </button>
      </div>
    </div>
  )
}

// ── Main page ─────────────────────────────────────────────────

export default function TopupPage() {
  const params = new URLSearchParams(window.location.search)
  const token = params.get('token')

  const [step, setStep] = useState('select') // select | qr | success
  const [order, setOrder] = useState(null)
  const [creditedSlots, setCreditedSlots] = useState(0)

  if (!token) {
    return (
      <div style={{ ...styles.container, paddingTop: 60 }}>
        <div style={styles.errorBox}>
          Không tìm thấy thông tin xác thực.<br />
          Vui lòng mở lại trang từ ứng dụng ShopHo.
        </div>
      </div>
    )
  }

  if (step === 'success') return <SuccessStep slots={creditedSlots} />

  if (step === 'qr') {
    return (
      <QRStep
        token={token}
        order={order}
        onSuccess={(data) => {
          setCreditedSlots(data.slots_amount)
          setStep('success')
        }}
        onBack={() => setStep('select')}
      />
    )
  }

  return (
    <PackageStep
      token={token}
      onOrderCreated={(data) => {
        setOrder(data)
        setStep('qr')
      }}
    />
  )
}

// ── Styles ────────────────────────────────────────────────────

const styles = {
  container: {
    maxWidth: 480,
    margin: '0 auto',
    padding: '24px 16px 40px',
  },
  header: {
    marginBottom: 28,
    textAlign: 'center',
  },
  logo: {
    display: 'inline-flex',
    alignItems: 'center',
    gap: 8,
    marginBottom: 16,
  },
  logoText: {
    fontWeight: 700,
    fontSize: 18,
    color: '#5B6AF0',
  },
  title: {
    fontSize: 22,
    fontWeight: 700,
    color: '#1a1a2e',
    marginBottom: 6,
  },
  subtitle: {
    fontSize: 14,
    color: '#666',
    lineHeight: 1.5,
  },
  packageList: {
    display: 'flex',
    flexDirection: 'column',
    gap: 12,
  },
  packageCard: {
    position: 'relative',
    background: '#fff',
    border: '1.5px solid #e8e8f0',
    borderRadius: 14,
    padding: '18px 16px',
    cursor: 'pointer',
    textAlign: 'left',
    width: '100%',
    transition: 'box-shadow 0.15s, border-color 0.15s',
    boxShadow: '0 1px 4px rgba(0,0,0,0.05)',
  },
  packageCardHighlight: {
    border: '2px solid #5B6AF0',
    boxShadow: '0 4px 16px rgba(91,106,240,0.15)',
  },
  badge: {
    position: 'absolute',
    top: -11,
    left: 16,
    color: '#fff',
    fontSize: 11,
    fontWeight: 600,
    padding: '2px 10px',
    borderRadius: 20,
  },
  packageTop: {
    display: 'flex',
    justifyContent: 'space-between',
    alignItems: 'center',
    marginBottom: 8,
  },
  slotCount: {
    display: 'flex',
    alignItems: 'baseline',
    gap: 4,
  },
  slotNumber: {
    fontSize: 32,
    fontWeight: 800,
    lineHeight: 1,
  },
  slotLabel: {
    fontSize: 14,
    color: '#666',
    fontWeight: 500,
  },
  priceBlock: {
    textAlign: 'right',
  },
  price: {
    display: 'block',
    fontSize: 18,
    fontWeight: 700,
    color: '#1a1a2e',
  },
  perSlot: {
    display: 'block',
    fontSize: 12,
    color: '#888',
    marginTop: 2,
  },
  packageDesc: {
    fontSize: 12,
    color: '#888',
  },
  errorBox: {
    marginTop: 16,
    background: '#fff5f5',
    border: '1px solid #fecaca',
    borderRadius: 10,
    padding: '12px 14px',
    color: '#dc2626',
    fontSize: 13,
    lineHeight: 1.5,
  },
  loadingOverlay: {
    marginTop: 24,
    display: 'flex',
    flexDirection: 'column',
    alignItems: 'center',
  },
  spinner: {
    width: 32,
    height: 32,
    border: '3px solid #e8e8f0',
    borderTop: '3px solid #5B6AF0',
    borderRadius: '50%',
    animation: 'spin 0.8s linear infinite',
  },
  spinnerSmall: {
    width: 16,
    height: 16,
    border: '2px solid #e8e8f0',
    borderTop: '2px solid #5B6AF0',
    borderRadius: '50%',
    animation: 'spin 0.8s linear infinite',
    flexShrink: 0,
  },
  backBtn: {
    display: 'inline-flex',
    alignItems: 'center',
    gap: 4,
    background: 'none',
    border: 'none',
    color: '#5B6AF0',
    fontSize: 14,
    fontWeight: 600,
    cursor: 'pointer',
    padding: '4px 0',
    marginBottom: 16,
  },
  qrCard: {
    background: '#fff',
    borderRadius: 16,
    padding: 20,
    boxShadow: '0 2px 12px rgba(0,0,0,0.07)',
  },
  qrInfo: {
    display: 'flex',
    justifyContent: 'space-between',
    alignItems: 'center',
    marginBottom: 16,
    padding: '10px 14px',
    background: '#f4f5ff',
    borderRadius: 10,
  },
  qrInfoLabel: {
    fontSize: 13,
    color: '#666',
  },
  qrInfoValue: {
    fontSize: 14,
    fontWeight: 600,
    color: '#5B6AF0',
  },
  qrImageWrap: {
    display: 'flex',
    justifyContent: 'center',
    marginBottom: 20,
  },
  qrImage: {
    width: 280,
    height: 280,
    borderRadius: 12,
    objectFit: 'contain',
  },
  bankInfo: {
    display: 'flex',
    flexDirection: 'column',
    gap: 10,
    marginBottom: 16,
  },
  bankRow: {
    display: 'flex',
    justifyContent: 'space-between',
    alignItems: 'center',
    fontSize: 14,
  },
  bankLabel: {
    color: '#888',
    fontSize: 13,
  },
  bankValue: {
    fontWeight: 600,
    color: '#1a1a2e',
  },
  codeRow: {
    display: 'flex',
    alignItems: 'center',
    gap: 8,
  },
  orderCode: {
    fontFamily: 'monospace',
    fontWeight: 700,
    fontSize: 15,
    color: '#5B6AF0',
    background: '#f4f5ff',
    padding: '2px 8px',
    borderRadius: 6,
  },
  copyBtn: {
    background: 'none',
    border: '1px solid #5B6AF0',
    color: '#5B6AF0',
    borderRadius: 6,
    padding: '2px 8px',
    fontSize: 12,
    cursor: 'pointer',
    fontWeight: 500,
  },
  waitingRow: {
    display: 'flex',
    alignItems: 'center',
    gap: 8,
    marginBottom: 12,
    padding: '10px 12px',
    background: '#f9fafb',
    borderRadius: 8,
  },
  note: {
    fontSize: 12,
    color: '#888',
    lineHeight: 1.6,
    textAlign: 'center',
  },
  successCard: {
    marginTop: 60,
    textAlign: 'center',
    padding: '0 16px',
  },
  successIcon: {
    width: 72,
    height: 72,
    background: '#22c55e',
    borderRadius: '50%',
    display: 'flex',
    alignItems: 'center',
    justifyContent: 'center',
    fontSize: 36,
    color: '#fff',
    margin: '0 auto 20px',
  },
  successTitle: {
    fontSize: 22,
    fontWeight: 700,
    color: '#1a1a2e',
    marginBottom: 10,
  },
  successMsg: {
    fontSize: 15,
    color: '#444',
    marginBottom: 8,
    lineHeight: 1.5,
  },
  successHint: {
    fontSize: 13,
    color: '#888',
    marginTop: 16,
  },
  backToAppBtn: {
    marginTop: 24,
    padding: '12px 28px',
    background: '#5B6AF0',
    color: '#fff',
    border: 'none',
    borderRadius: 12,
    fontSize: 15,
    fontWeight: 600,
    cursor: 'pointer',
  },
}

// inject keyframe animation for spinner
const styleEl = document.createElement('style')
styleEl.textContent = `@keyframes spin { to { transform: rotate(360deg); } }`
document.head.appendChild(styleEl)
