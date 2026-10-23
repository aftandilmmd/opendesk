-- A deleted message stays as a marker in its conversation: who deleted it and when. Agents
-- see only the marker; admins can read it and bring it back.
ALTER TABLE messages ADD COLUMN deleted_at timestamptz;
ALTER TABLE messages ADD COLUMN deleted_by uuid REFERENCES users(id) ON DELETE SET NULL;
