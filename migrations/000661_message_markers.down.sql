ALTER TABLE members DROP COLUMN message_delete;
ALTER TABLE messages DROP COLUMN sent_as_reply_id;
ALTER TABLE messages DROP COLUMN purged_at;
ALTER TABLE messages DROP COLUMN deleted_by;
ALTER TABLE messages DROP COLUMN deleted_at;
