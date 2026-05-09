-- Migration 005: replace JSONB filter columns with a normalised locations table
-- This enables efficient B-tree index lookups instead of full-table JSONB scans.

-- 1. Create the new locations table
CREATE TABLE IF NOT EXISTS shipper_alert_locations (
    id           UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id      UUID        NOT NULL REFERENCES users(id)       ON DELETE CASCADE,
    apartment_id UUID        NOT NULL REFERENCES apartments(id)  ON DELETE CASCADE,
    building     VARCHAR(20),          -- NULL = any building in this apartment
    floor        SMALLINT              -- NULL = any floor
);

-- Unique index (COALESCE so NULLs compare as equal within the same user+apt scope)
CREATE UNIQUE INDEX IF NOT EXISTS idx_sal_unique
    ON shipper_alert_locations(
        user_id,
        apartment_id,
        COALESCE(building, ''),
        COALESCE(floor, -1)
    );

-- Index used by the push-notification query
CREATE INDEX IF NOT EXISTS idx_sal_apt_building
    ON shipper_alert_locations(apartment_id, building);

-- 2. Migrate existing data ---------------------------------------------------

-- apartment_ids (whole-apt rows) – no floor filter
INSERT INTO shipper_alert_locations (user_id, apartment_id, building, floor)
SELECT sa.user_id,
       apt_id::UUID,
       NULL::VARCHAR,
       NULL::SMALLINT
FROM   shipper_alerts sa,
       jsonb_array_elements_text(sa.apartment_ids) AS apt_id
WHERE  jsonb_array_length(sa.apartment_ids) > 0
  AND  (sa.floors IS NULL OR jsonb_array_length(sa.floors) = 0)
ON CONFLICT DO NOTHING;

-- apartment_ids – with floor filter (cross product apt × floor)
INSERT INTO shipper_alert_locations (user_id, apartment_id, building, floor)
SELECT sa.user_id,
       apt_id::UUID,
       NULL::VARCHAR,
       f::TEXT::SMALLINT
FROM   shipper_alerts sa,
       jsonb_array_elements_text(sa.apartment_ids) AS apt_id,
       jsonb_array_elements(sa.floors)             AS f
WHERE  jsonb_array_length(sa.apartment_ids) > 0
  AND  sa.floors IS NOT NULL
  AND  jsonb_array_length(sa.floors) > 0
ON CONFLICT DO NOTHING;

-- building_keys ("apt_uuid:building_name") – no floor filter
INSERT INTO shipper_alert_locations (user_id, apartment_id, building, floor)
SELECT sa.user_id,
       split_part(bk, ':', 1)::UUID,
       split_part(bk, ':', 2),
       NULL::SMALLINT
FROM   shipper_alerts sa,
       jsonb_array_elements_text(sa.building_keys) AS bk
WHERE  jsonb_array_length(sa.building_keys) > 0
  AND  (sa.floors IS NULL OR jsonb_array_length(sa.floors) = 0)
ON CONFLICT DO NOTHING;

-- building_keys – with floor filter
INSERT INTO shipper_alert_locations (user_id, apartment_id, building, floor)
SELECT sa.user_id,
       split_part(bk, ':', 1)::UUID,
       split_part(bk, ':', 2),
       f::TEXT::SMALLINT
FROM   shipper_alerts sa,
       jsonb_array_elements_text(sa.building_keys) AS bk,
       jsonb_array_elements(sa.floors)             AS f
WHERE  jsonb_array_length(sa.building_keys) > 0
  AND  sa.floors IS NOT NULL
  AND  jsonb_array_length(sa.floors) > 0
ON CONFLICT DO NOTHING;

-- 3. Drop the old JSONB columns from shipper_alerts
ALTER TABLE shipper_alerts
    DROP COLUMN IF EXISTS apartment_ids,
    DROP COLUMN IF EXISTS building_keys,
    DROP COLUMN IF EXISTS floors;
