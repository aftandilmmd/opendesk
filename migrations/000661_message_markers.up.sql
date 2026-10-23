-- A deleted message stays as a marker in its conversation: who deleted it and when. Agents
-- see only the marker; admins can read it and bring it back.
ALTER TABLE messages ADD COLUMN deleted_at timestamptz;
ALTER TABLE messages ADD COLUMN deleted_by uuid REFERENCES users(id) ON DELETE SET NULL;
-- An admin can remove what a deleted message said for good: its text, its files and the
-- original email it came in. The marker stays, with when it was emptied.
ALTER TABLE messages ADD COLUMN purged_at timestamptz;
-- A note sent as a reply stays where it was as a marker pointing at the reply. Its own
-- words are kept and hidden like a deleted message's.
ALTER TABLE messages ADD COLUMN sent_as_reply_id uuid REFERENCES messages(id) ON DELETE SET NULL;
-- A member's own rule for which messages they may delete, over the workspace's
-- (settings.message_delete). NULL follows the workspace.
ALTER TABLE members ADD COLUMN message_delete text CHECK (message_delete IN ('off', 'own', 'all'));
