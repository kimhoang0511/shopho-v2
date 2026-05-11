CREATE TABLE IF NOT EXISTS deleted_account_slots (
    phone       TEXT        PRIMARY KEY,
    order_slots SMALLINT    NOT NULL,
    deleted_at  TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
