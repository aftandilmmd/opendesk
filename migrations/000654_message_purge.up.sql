-- An admin can remove what a deleted message said for good: its text, its files and the
-- original email it came in. The marker stays, with when it was emptied.
ALTER TABLE messages ADD COLUMN purged_at timestamptz;
