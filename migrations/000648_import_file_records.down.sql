DROP INDEX IF EXISTS attachments_imported_idx;
ALTER TABLE attachments DROP COLUMN IF EXISTS imported;
DELETE FROM import_records WHERE kind = 'file';
ALTER TABLE import_records DROP CONSTRAINT import_records_kind_check;
ALTER TABLE import_records ADD CONSTRAINT import_records_kind_check
    CHECK (kind IN ('ticket', 'message', 'contact', 'company', 'tag', 'article', 'collection'));
