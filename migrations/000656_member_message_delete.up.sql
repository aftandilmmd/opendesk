-- A member's own rule for which messages they may delete, over the workspace's
-- (settings.message_delete). NULL follows the workspace.
ALTER TABLE members ADD COLUMN message_delete text CHECK (message_delete IN ('off', 'own', 'all'));
