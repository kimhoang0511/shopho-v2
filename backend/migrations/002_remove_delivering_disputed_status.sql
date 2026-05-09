-- Remove delivering and disputed from OrderStatus enum.
-- delivering → accepted  (in-progress orders)
-- disputed   → cancelled

UPDATE orders SET status = 'accepted'  WHERE status = 'delivering';
UPDATE orders SET status = 'cancelled' WHERE status = 'disputed';

-- Drop partial indexes that reference the old enum type
DROP INDEX IF EXISTS uq_order_shipper;
DROP INDEX IF EXISTS idx_orders_pending_building;
DROP INDEX IF EXISTS idx_orders_expires;
DROP INDEX IF EXISTS idx_orders_note_trgm;
DROP INDEX IF EXISTS idx_orders_market_price;
DROP INDEX IF EXISTS idx_orders_autocomplete_delivering;
DROP INDEX IF EXISTS idx_orders_autocomplete_accepted;

-- Recreate enum type without the removed values
ALTER TABLE orders ALTER COLUMN status DROP DEFAULT;
ALTER TYPE order_status RENAME TO order_status_old;
CREATE TYPE order_status AS ENUM ('pending', 'accepted', 'completed', 'cancelled', 'expired');
ALTER TABLE orders ALTER COLUMN status TYPE order_status USING status::text::order_status;
ALTER TABLE orders ALTER COLUMN status SET DEFAULT 'pending'::order_status;
DROP TYPE order_status_old;

-- Recreate indexes with updated type
CREATE UNIQUE INDEX uq_order_shipper           ON orders (id) WHERE status = 'accepted';
CREATE INDEX idx_orders_pending_building        ON orders (ship_building, created_at DESC) WHERE status = 'pending';
CREATE INDEX idx_orders_expires                 ON orders (expires_at) WHERE status = 'pending';
CREATE INDEX idx_orders_note_trgm               ON orders USING gin (note gin_trgm_ops) WHERE status = 'pending';
CREATE INDEX idx_orders_market_price            ON orders (ship_apartment_id, ship_location, created_at DESC) WHERE status = ANY (ARRAY['accepted'::order_status, 'completed'::order_status]);
CREATE INDEX idx_orders_autocomplete_accepted   ON orders (accepted_at) WHERE status = 'accepted';
