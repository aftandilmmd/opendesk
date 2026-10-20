package hd

import (
	"bytes"
	"context"
	"fmt"
	"io"
	"mime"
	"net/http"
	"path"
	"path/filepath"
	"slices"
	"strings"
	"unicode"

	"github.com/google/uuid"

	"github.com/useopendesk/opendesk/internal/db"
	"github.com/useopendesk/opendesk/internal/domain"
	"github.com/useopendesk/opendesk/internal/httpx"
	"github.com/useopendesk/opendesk/internal/ids"
	"github.com/useopendesk/opendesk/internal/storage"
)

// MaxAttachmentBytes is the upload limit per file.
const MaxAttachmentBytes = 25 << 20

// Extensions that run code when opened. Refused regardless of the bytes.
var executableExt = []string{
	".exe", ".dll", ".com", ".bat", ".cmd", ".msi", ".msp", ".scr", ".pif", ".cpl", ".hta", ".jar", ".js", ".jse",
	".vbs", ".vbe", ".wsf", ".wsh", ".ps1", ".psm1", ".sh", ".bash", ".zsh", ".csh", ".ksh", ".app", ".apk", ".deb", ".rpm",
	".lnk", ".reg", ".scf", ".gadget", ".msc", ".dmg", ".pkg", ".elf", ".bin", ".run", ".command", ".appimage", ".sys", ".drv", ".ocx",
}

// Types that a browser would render as an active document; stored, never served inline,
// and labelled by their safe type.
var activeTypes = []string{"text/html", "image/svg+xml", "application/xhtml+xml", "text/xml", "application/xml", "text/javascript", "application/javascript"}

// InlineSafe reports content types served inline (raster images only).
func InlineSafe(ct string) bool {
	switch strings.ToLower(strings.TrimSpace(strings.Split(ct, ";")[0])) {
	case "image/png", "image/jpeg", "image/gif", "image/webp", "image/avif", "image/bmp":
		return true
	}
	return false
}

// IsExecutable reports whether the first bytes or the name say the file is a program.
func IsExecutable(head []byte, filename string) bool {
	if slices.Contains(executableExt, strings.ToLower(filepath.Ext(filename))) {
		return true
	}
	magic := [][]byte{
		[]byte("MZ"),               // PE / DOS
		[]byte("\x7fELF"),          // ELF
		{0xfe, 0xed, 0xfa, 0xce},   // Mach-O 32
		{0xfe, 0xed, 0xfa, 0xcf},   // Mach-O 64
		{0xce, 0xfa, 0xed, 0xfe},   // Mach-O 32 LE
		{0xcf, 0xfa, 0xed, 0xfe},   // Mach-O 64 LE
		{0xca, 0xfe, 0xba, 0xbe},   // Mach-O universal / Java class
		[]byte("#!"),               // scripts
		{0x00, 0x61, 0x73, 0x6d},   // wasm
		[]byte("dex\n"),            // Android dex
		{0x4c, 0x00, 0x00, 0x00},   // Windows shortcut
		[]byte("\xd0\xcf\x11\xe0"), // OLE: msi, legacy office; allowed only with a document name, below
	}
	for i, m := range magic {
		if bytes.HasPrefix(head, m) {
			if i == len(magic)-1 {
				ext := strings.ToLower(filepath.Ext(filename))
				return !slices.Contains([]string{".doc", ".xls", ".ppt", ".msg", ".vsd", ".pub"}, ext)
			}
			return true
		}
	}
	return false
}

// CleanFilename keeps the base name, without control or path characters, max 200 runes.
func CleanFilename(name string) string {
	name = path.Base(strings.ReplaceAll(name, `\`, "/"))
	name = strings.Map(func(r rune) rune {
		if unicode.IsControl(r) || strings.ContainsRune(`/\:*?"<>|`, r) || unicode.In(r, unicode.Cf) {
			return -1
		}
		return r
	}, name)
	name = strings.TrimSpace(strings.Trim(name, "."))
	if name == "" || name == "." {
		name = "file"
	}
	return Truncate(name, 200)
}

// DetectType picks the stored content type from the bytes, using the name only to
// refine a generic sniff. Active document types are stored as plain or binary.
func DetectType(head []byte, filename string) string {
	ct := http.DetectContentType(head)
	base := strings.ToLower(strings.TrimSpace(strings.Split(ct, ";")[0]))
	if base == "application/octet-stream" || base == "text/plain" || base == "application/zip" {
		if byExt := mime.TypeByExtension(strings.ToLower(filepath.Ext(filename))); byExt != "" {
			b := strings.ToLower(strings.TrimSpace(strings.Split(byExt, ";")[0]))
			if !slices.Contains(activeTypes, b) && !(base == "text/plain" && !strings.HasPrefix(b, "text/")) {
				ct, base = byExt, b
			}
		}
	}
	if slices.Contains(activeTypes, base) {
		if strings.HasPrefix(base, "text/") {
			return "text/plain; charset=utf-8"
		}
		return "application/octet-stream"
	}
	return ct
}

// Upload is a file arriving from a client.
type Upload struct {
	WorkspaceID       uuid.UUID
	UploadedBy        *uuid.UUID // agent
	UploadedByAPIKey  *uuid.UUID // API key
	UploadedByContact *uuid.UUID // widget visitor
	Filename          string
	Size              int64
	Body              io.Reader
	// Types limits the upload to these FileTypes ids; nil takes any file but a program.
	Types []string
}

// SaveUpload sniffs, refuses executables, stores the object under
// workspaces/<wid>/attachments/<id> and inserts an unattached attachment row.
func SaveUpload(ctx context.Context, st storage.Storage, q db.Querier, up Upload) (domain.Attachment, error) {
	if up.Size > MaxAttachmentBytes {
		return domain.Attachment{}, httpx.E(413, "too_large", "Files can be at most 25 MB.")
	}
	if up.Size <= 0 {
		return domain.Attachment{}, httpx.Validation("the file is empty")
	}
	filename := CleanFilename(up.Filename)
	head := make([]byte, 512)
	n, err := io.ReadFull(up.Body, head)
	if err != nil && err != io.ErrUnexpectedEOF && err != io.EOF {
		return domain.Attachment{}, fmt.Errorf("read upload: %w", err)
	}
	head = head[:n]
	if IsExecutable(head, filename) {
		return domain.Attachment{}, httpx.E(422, "file_type_refused", "Executable files and scripts cannot be attached.")
	}
	if up.Types != nil && !FileTypeAllowed(head, filename, up.Types) {
		return domain.Attachment{}, httpx.E(422, "file_type_not_allowed", "This type of file can't be sent here.")
	}
	ct := DetectType(head, filename)
	id := ids.New()
	key := "workspaces/" + up.WorkspaceID.String() + "/attachments/" + id.String()
	body := io.LimitReader(io.MultiReader(bytes.NewReader(head), up.Body), MaxAttachmentBytes+1)
	counter := &countingReader{r: body}
	if err := st.Put(ctx, key, counter, up.Size, ct); err != nil {
		return domain.Attachment{}, fmt.Errorf("store upload: %w", err)
	}
	if counter.n > MaxAttachmentBytes {
		_ = st.Delete(context.WithoutCancel(ctx), key)
		return domain.Attachment{}, httpx.E(413, "too_large", "Files can be at most 25 MB.")
	}
	if _, err := q.Exec(ctx, `INSERT INTO attachments (id, workspace_id, filename, content_type, size_bytes, storage_key,
		uploaded_by, uploaded_by_contact_id, uploaded_by_api_key_id) VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9)`,
		id, up.WorkspaceID, filename, ct, counter.n, key, up.UploadedBy, up.UploadedByContact, up.UploadedByAPIKey); err != nil {
		_ = st.Delete(context.WithoutCancel(ctx), key)
		return domain.Attachment{}, fmt.Errorf("insert attachment: %w", err)
	}
	return domain.Attachment{ID: id, Filename: filename, ContentType: ct, SizeBytes: counter.n, URL: domain.AttachmentURL(id)}, nil
}

type countingReader struct {
	r io.Reader
	n int64
}

func (c *countingReader) Read(p []byte) (int, error) {
	n, err := c.r.Read(p)
	c.n += int64(n)
	return n, err
}

// ParseAttachmentIDs parses body ids, deduplicated.
func ParseAttachmentIDs(raw []string) ([]uuid.UUID, error) {
	if len(raw) > 20 {
		return nil, httpx.Validation("at most 20 attachments per message")
	}
	out := make([]uuid.UUID, 0, len(raw))
	for _, s := range raw {
		id, err := ParseRef(s, "attachment_ids")
		if err != nil {
			return nil, err
		}
		if !slices.Contains(out, id) {
			out = append(out, id)
		}
	}
	return out, nil
}

// Uploader is who made an upload: an agent, an API key or a widget visitor.
type Uploader struct {
	User, APIKey, Contact *uuid.UUID
}

// CheckAttachments confirms every id is an unattached upload in the workspace made by by:
// the same agent, API key or visitor (contracts/api.md "Attachments").
func CheckAttachments(ctx context.Context, q db.Querier, wid uuid.UUID, attIDs []uuid.UUID, by Uploader) error {
	if len(attIDs) == 0 {
		return nil
	}
	var n int
	if err := q.QueryRow(ctx, `SELECT count(*) FROM attachments WHERE workspace_id = $1 AND id = ANY($2) AND message_id IS NULL
		AND uploaded_by IS NOT DISTINCT FROM $3 AND uploaded_by_api_key_id IS NOT DISTINCT FROM $4
		AND uploaded_by_contact_id IS NOT DISTINCT FROM $5`, wid, attIDs, by.User, by.APIKey, by.Contact).Scan(&n); err != nil {
		return err
	}
	if n != len(attIDs) {
		return httpx.Validation("attachment_ids must be your uploads that are not attached to a message yet")
	}
	return nil
}
