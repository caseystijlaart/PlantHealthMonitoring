-- PlantHealthMonitor — Supabase migrations
-- Run these once in the Supabase SQL editor (or via supabase db push).
-- Steps are idempotent where noted; run them in order.

-- ─────────────────────────────────────────────────────────────────────────────
-- Step 1: Widen device_id from integer → text
--
-- The two existing columns were populated with integer values 1 and 2
-- (DEVICE_ID=1 / DEVICE_ID=2 from platformio.ini).  Widening to text lets the
-- same column hold both legacy short IDs ("1", "2") and new UUID strings
-- assigned during BLE provisioning.
-- ─────────────────────────────────────────────────────────────────────────────

ALTER TABLE plant_settings
  ALTER COLUMN device_id TYPE text USING device_id::text;

ALTER TABLE plant_readings
  ALTER COLUMN device_id TYPE text USING device_id::text;


-- ─────────────────────────────────────────────────────────────────────────────
-- Step 2: Create the devices table
-- ─────────────────────────────────────────────────────────────────────────────

CREATE TABLE IF NOT EXISTS devices (
  device_id           text        PRIMARY KEY,
  status              text        NOT NULL DEFAULT 'provisioning',
                                  -- 'provisioning' → awaiting WiFi connect
                                  -- 'active'        → online and sending readings
  registered_at       timestamptz          DEFAULT now(),
  last_seen           timestamptz,
  trigger_measurement boolean     NOT NULL DEFAULT false
                                  -- app sets true → firmware runs an immediate
                                  -- measurement cycle, then resets to false
);


-- ─────────────────────────────────────────────────────────────────────────────
-- Step 3: Seed the two existing legacy devices
--
-- These correspond to the hardcoded DEVICE_ID=1 and DEVICE_ID=2 environments
-- in platformio.ini (PeaceLily and PrayerPlant).  Must be inserted before
-- adding the foreign-key constraint below.
-- ─────────────────────────────────────────────────────────────────────────────

INSERT INTO devices (device_id, status)
  VALUES ('1', 'active'),
         ('2', 'active')
  ON CONFLICT (device_id) DO NOTHING;


-- ─────────────────────────────────────────────────────────────────────────────
-- Step 4: Add foreign-key constraints → devices
--
-- plant_settings:  one device per plant; unlinking a device keeps the plant row.
-- plant_readings:  historical readings are retained if a device is deleted,
--                  device_id is simply nulled out.
--
-- Skip this step if you prefer a looser schema (e.g. while testing).
-- ─────────────────────────────────────────────────────────────────────────────

ALTER TABLE plant_settings
  ADD CONSTRAINT fk_plant_settings_device
  FOREIGN KEY (device_id) REFERENCES devices (device_id)
  ON DELETE SET NULL;

-- plant_readings intentionally has no FK to devices.
-- Historical readings are kept as-is when a device is deleted — the device_id
-- becomes an orphaned reference which is fine for audit/history purposes.
-- An ON DELETE SET NULL cascade here would require UPDATE permission on
-- plant_readings which RLS does not grant to the client.


-- ─────────────────────────────────────────────────────────────────────────────
-- Step 5: Add trigger_reset flag to devices
--
-- The app sets this to true when a user removes a device from the Settings
-- "Connected Devices" section.  The ESP32 firmware polls for this flag; when
-- it sees true it wipes its NVS (WiFi credentials + device_id) and reboots
-- into provisioning mode, making it available for a new user.
--
-- The device row and all plant_readings are intentionally kept.
-- ─────────────────────────────────────────────────────────────────────────────

ALTER TABLE devices
  ADD COLUMN IF NOT EXISTS trigger_reset boolean NOT NULL DEFAULT false;


-- ─────────────────────────────────────────────────────────────────────────────
-- Step 6 (revised): Drop the FK from plant_readings → devices
--
-- The ON DELETE SET NULL cascade requires UPDATE permission on plant_readings,
-- which RLS does not grant to the anon/client role.  Deleting a device row
-- would fail with "cannot update table plant_readings".
-- Historical readings are kept as orphaned rows — device_id becomes a soft
-- reference only.  Run this if you applied the FK in Step 4.
-- ─────────────────────────────────────────────────────────────────────────────

ALTER TABLE plant_readings
  DROP CONSTRAINT IF EXISTS fk_plant_readings_device;


-- ─────────────────────────────────────────────────────────────────────────────
-- Step 6: Ensure plant_settings.id auto-increments
--
-- The id column was created as plain int8 with no default, causing inserts
-- that omit it to fail with a not-null violation.  This creates a sequence
-- (if one doesn't already exist), resets it to a safe start value, and sets
-- it as the column default so new rows get an id automatically.
-- ─────────────────────────────────────────────────────────────────────────────

CREATE SEQUENCE IF NOT EXISTS plant_settings_id_seq;

SELECT setval(
  'plant_settings_id_seq',
  COALESCE((SELECT MAX(id) FROM plant_settings), 0) + 1,
  false
);

ALTER TABLE plant_settings
  ALTER COLUMN id SET DEFAULT nextval('plant_settings_id_seq');


-- ─────────────────────────────────────────────────────────────────────────────
-- Step 7: Add device_name to devices
--
-- A human-readable name for the device (the BLE advertised name, e.g.
-- "PlantMonitor-1A2B").  Written by the app right after the firmware registers
-- the device during provisioning.  Makes devices recognisable in the app and
-- dev dashboard without having to compare long UUIDs.
-- ─────────────────────────────────────────────────────────────────────────────

ALTER TABLE devices
  ADD COLUMN IF NOT EXISTS device_name text;

-- Optional: name the two legacy devices.
UPDATE devices SET device_name = 'PeaceLily sensor'   WHERE device_id = '1' AND device_name IS NULL;
UPDATE devices SET device_name = 'PrayerPlant sensor' WHERE device_id = '2' AND device_name IS NULL;
