-- Migration 007: slot top-up orders table
-- Tracks pending/completed slot purchase transactions.

CREATE TABLE IF NOT EXISTS slot_topup_orders (
    id           UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id      UUID        NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    order_code   VARCHAR(20) UNIQUE NOT NULL,
    slots_amount INTEGER     NOT NULL,
    amount_vnd   INTEGER     NOT NULL,
    status       VARCHAR(20) NOT NULL DEFAULT 'pending',
    created_at   TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    completed_at TIMESTAMPTZ
);

CREATE INDEX IF NOT EXISTS idx_slot_topup_user ON slot_topup_orders(user_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_slot_topup_code ON slot_topup_orders(order_code) WHERE status = 'pending';
