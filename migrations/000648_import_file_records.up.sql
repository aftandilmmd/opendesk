-- An import remembers every file it copies, so a ticket whose files take more than one run
-- picks up where it stopped. The files imports copied are marked: they count against the
-- plan's import limit for as long as they are kept.
ALTER TABLE import_records DROP CONSTRAINT import_records_kind_check;
ALTER TABLE import_records ADD CONSTRAINT import_records_kind_check
    CHECK (kind IN ('ticket', 'message', 'contact', 'company', 'tag', 'article', 'collection', 'file'));
ALTER TABLE attachments ADD COLUMN imported boolean NOT NULL DEFAULT false;
CREATE INDEX attachments_imported_idx ON attachments(workspace_id) WHERE imported;
