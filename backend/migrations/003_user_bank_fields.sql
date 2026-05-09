ALTER TABLE users
    ADD COLUMN IF NOT EXISTS bank_code            VARCHAR(50),
    ADD COLUMN IF NOT EXISTS bank_account_number  VARCHAR(30),
    ADD COLUMN IF NOT EXISTS bank_account_name    VARCHAR(100);

-- Add total_gold to orders (recorded by shipper on delivery)
ALTER TABLE orders ADD COLUMN IF NOT EXISTS total_gold NUMERIC(8,2);
