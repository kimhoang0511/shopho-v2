ALTER TABLE shipper_alerts
    ADD COLUMN IF NOT EXISTS min_gold NUMERIC(8,2);
