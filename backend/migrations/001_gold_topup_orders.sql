-- Gold top-up orders: track pending/completed VietQR payments
CREATE TABLE IF NOT EXISTS gold_topup_orders (
    id              UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id         UUID        NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    order_code      VARCHAR(20) NOT NULL UNIQUE,
    gold_amount     NUMERIC(10, 2) NOT NULL,
    amount_vnd      INTEGER     NOT NULL,
    status          VARCHAR(20) NOT NULL DEFAULT 'pending',  -- pending | completed | expired
    created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    completed_at    TIMESTAMPTZ
);

CREATE INDEX IF NOT EXISTS idx_topup_order_code ON gold_topup_orders(order_code);
CREATE INDEX IF NOT EXISTS idx_topup_user      ON gold_topup_orders(user_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_topup_pending   ON gold_topup_orders(status, created_at)
    WHERE status = 'pending';
