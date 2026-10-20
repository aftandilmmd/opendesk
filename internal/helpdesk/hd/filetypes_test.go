package hd_test

import (
	"slices"
	"testing"

	"github.com/useopendesk/opendesk/internal/helpdesk/hd"
)

func TestFileTypeAllowed(t *testing.T) {
	all := hd.DefaultFileTypes()
	ok := []struct {
		name string
		head string
	}{
		{"shot.png", "\x89PNG\r\n\x1a\n\x00\x00"},
		{"photo.JPEG", "\xff\xd8\xff\xe0\x00\x10JFIF"},
		{"photo.jpg", "\xff\xd8\xff\xe1"},
		{"anim.gif", "GIF89a\x01\x00"},
		{"pic.webp", "RIFF\x24\x00\x00\x00WEBPVP8 "},
		{"phone.heic", "\x00\x00\x00\x18ftypheic\x00\x00\x00\x00"},
		{"invoice.pdf", "%PDF-1.7\n"},
		{"notes.txt", "Hello, this is plain text.\nŞükrü çalışıyor"},
		{"data.csv", "id,name\n1,Ada\n"},
		{"letter.rtf", "{\\rtf1\\ansi"},
		{"old.doc", "\xd0\xcf\x11\xe0\xa1\xb1\x1a\xe1"},
		{"new.docx", "PK\x03\x04\x14\x00"},
		{"sheet.xlsx", "PK\x03\x04\x14\x00"},
		{"deck.pptx", "PK\x03\x04\x14\x00"},
		{"files.zip", "PK\x03\x04\x14\x00"},
		{"clip.mp4", "\x00\x00\x00\x20ftypisom\x00\x00"},
		{"clip.mov", "\x00\x00\x00\x14ftypqt  \x00\x00"},
		{"voice.mp3", "ID3\x04\x00"},
		{"voice.m4a", "\x00\x00\x00\x20ftypM4A \x00\x00"},
		{"call.wav", "RIFF\x24\x00\x00\x00WAVEfmt "},
	}
	for _, c := range ok {
		if !hd.FileTypeAllowed([]byte(c.head), c.name, all) {
			t.Errorf("%s refused", c.name)
		}
	}

	refused := []struct {
		name string
		head string
	}{
		{"shell.png", "#!/bin/sh\nrm -rf /"},            // a script named as an image
		{"page.png", "<html><script>x</script></html>"}, // markup named as an image
		{"tool.pdf", "MZ\x90\x00"},                      // a program named as a document
		{"run.jpg", "\x7fELF\x02\x01"},                  // ELF named as an image
		{"notes.txt", "MZ\x90\x00\x03\x00\x00\x00"},     // binary named as text
		{"notes.txt", "hello\x00world"},                 // NUL in text
		{"notes.txt", "\xff\xfe\xfdnot utf-8"},          // not UTF-8
		{"pic.webp", "RIFF\x24\x00\x00\x00WAVEfmt "},    // wrong RIFF kind
		{"phone.heic", "\x00\x00\x00\x20ftypisom\x00\x00"},
		{"payload.svg", "<svg onload=alert(1)>"}, // not in the catalog
		{"page.html", "<html></html>"},
		{"script.js", "alert(1)"},
		{"archive.rar", "Rar!\x1a\x07\x00"},
		{"noextension", "%PDF-1.7"},
		{"invoice.pdf.exe", "%PDF-1.7"},
		{"invoice.pdf", ""},
	}
	for _, c := range refused {
		if hd.FileTypeAllowed([]byte(c.head), c.name, all) {
			t.Errorf("%s (%q) allowed", c.name, c.head)
		}
	}

	// Only the picked types.
	if hd.FileTypeAllowed([]byte("%PDF-1.7"), "a.pdf", []string{"png", "jpg"}) {
		t.Fatal("pdf allowed with images only")
	}
	if !hd.FileTypeAllowed([]byte("\x89PNG\r\n\x1a\n"), "a.png", []string{"png", "jpg"}) {
		t.Fatal("png refused with images only")
	}
	if hd.FileTypeAllowed([]byte("\x89PNG\r\n\x1a\n"), "a.png", nil) {
		t.Fatal("allowed with no types")
	}
}

func TestFileTypeCatalog(t *testing.T) {
	ids := hd.DefaultFileTypes()
	if len(ids) != len(hd.FileTypes()) || !slices.Contains(ids, "pdf") || slices.Contains(ids, "svg") {
		t.Fatal(ids)
	}
	got := hd.FileTypeExtensions([]string{"jpg", "pdf", "nope"})
	if !slices.Equal(got, []string{".jpg", ".jpeg", ".pdf"}) {
		t.Fatal(got)
	}
	if v, err := hd.CleanFileTypes([]string{"pdf", "png", "pdf"}); err != nil || !slices.Equal(v, []string{"png", "pdf"}) {
		t.Fatal(v, err)
	}
	for _, bad := range [][]string{{}, {"exe"}, {"png", "svg"}} {
		if _, err := hd.CleanFileTypes(bad); err == nil {
			t.Fatalf("%v accepted", bad)
		}
	}
}
