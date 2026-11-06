-- The end of a wait a mail provider asked for (a rate limit's Retry-After): no call is made
-- for the account until then, from any server.
ALTER TABLE collab_accounts ADD COLUMN IF NOT EXISTS provider_wait_until timestamptz;
