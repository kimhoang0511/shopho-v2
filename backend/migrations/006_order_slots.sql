-- Migration 006: add order_slots balance to users
-- New users start with 5 free slots; existing users get 5 as well.

ALTER TABLE users
    ADD COLUMN IF NOT EXISTS order_slots INTEGER NOT NULL DEFAULT 5;
