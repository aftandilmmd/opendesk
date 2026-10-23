-- A note sent as a reply stays where it was as a marker pointing at the reply, which now
-- holds its words.
ALTER TABLE messages ADD COLUMN sent_as_reply_id uuid REFERENCES messages(id) ON DELETE SET NULL;
