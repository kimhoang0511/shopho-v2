-- Add ios_voip to device_tokens platform CHECK constraint.
-- VoIP (PushKit) tokens must be registered separately from regular FCM tokens
-- because they use APNs directly and require a different send path.
ALTER TABLE device_tokens DROP CONSTRAINT IF EXISTS device_tokens_platform_check;
ALTER TABLE device_tokens ADD CONSTRAINT device_tokens_platform_check
    CHECK (platform = ANY (ARRAY['ios', 'android', 'macos', 'web', 'ios_voip']));
