-- When the visitor last read a chat (contracts/api.md "Widget"): the widget counts the team's
-- replies after it as unread, and agents see whether their message was seen. Existing chats
-- start read, so nothing old shows as new.
ALTER TABLE tickets ADD COLUMN visitor_read_at timestamptz;
UPDATE tickets SET visitor_read_at = last_message_at WHERE channel = 'chat';
