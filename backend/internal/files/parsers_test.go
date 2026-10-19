package files

import (
	"archive/zip"
	"bytes"
	"compress/zlib"
	"fmt"
	"strings"
	"testing"
)

func TestDetectFileTypeAndValidate(t *testing.T) {
	tests := []struct {
		name        string
		header      []byte
		filename    string
		wantType    FileType
		wantMime    string
		wantErr     bool
	}{
		{
			name:     "Valid PDF",
			header:   []byte("%PDF-1.4\n%...\n"),
			filename: "document.pdf",
			wantType: FileTypePDF,
			wantMime: "application/pdf",
		},
		{
			name:     "Valid PNG",
			header:   []byte("\x89PNG\r\n\x1a\n\x00\x00\x00\rIHDR"),
			filename: "avatar.png",
			wantType: FileTypeImage,
			wantMime: "image/png",
		},
		{
			name:     "Valid JPEG",
			header:   []byte("\xFF\xD8\xFF\xE0\x00\x10JFIF"),
			filename: "photo.jpg",
			wantType: FileTypeImage,
			wantMime: "image/jpeg",
		},
		{
			name:     "Valid WEBP",
			header:   []byte("RIFF\x00\x00\x00\x00WEBP"),
			filename: "graphic.webp",
			wantType: FileTypeImage,
			wantMime: "image/webp",
		},
		{
			name:     "Valid DOCX",
			header:   []byte("PK\x03\x04\x14\x00\x06\x00"),
			filename: "proposal.docx",
			wantType: FileTypeDOCX,
			wantMime: "application/vnd.openxmlformats-officedocument.wordprocessingml.document",
		},
		{
			name:     "Valid CSV",
			header:   []byte("id,name,value\n1,Alice,100\n"),
			filename: "data.csv",
			wantType: FileTypeText,
			wantMime: "text/csv",
		},
		{
			name:     "Valid Text",
			header:   []byte("Assalomu alaykum, bu oddiy matn fayli."),
			filename: "notes.txt",
			wantType: FileTypeText,
			wantMime: "text/plain",
		},
		{
			name:     "Unsupported Binary Executable",
			header:   []byte("\x7fELF\x02\x01\x01\x00"),
			filename: "program.exe",
			wantErr:  true,
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			ft, mime, err := DetectFileTypeAndValidate(tt.header, tt.filename)
			if tt.wantErr {
				if err == nil {
					t.Errorf("expected error, got nil")
				}
				return
			}
			if err != nil {
				t.Fatalf("unexpected error: %v", err)
			}
			if ft != tt.wantType {
				t.Errorf("got type %v, want %v", ft, tt.wantType)
			}
			if mime != tt.wantMime {
				t.Errorf("got mime %v, want %v", mime, tt.wantMime)
			}
		})
	}
}

func TestExtractDocxContent(t *testing.T) {
	// Create mock DOCX in memory
	var buf bytes.Buffer
	zw := zip.NewWriter(&buf)

	w, err := zw.Create("word/document.xml")
	if err != nil {
		t.Fatalf("failed to create zip entry: %v", err)
	}

	mockXML := `<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<w:document xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main">
    <w:body>
        <w:p><w:r><w:t>Loyiha hisoboti va rejalari</w:t></w:r></w:p>
        <w:tbl>
            <w:tr>
                <w:tc><w:p><w:r><w:t>Bosqich</w:t></w:r></w:p></w:tc>
                <w:tc><w:p><w:r><w:t>Muddat</w:t></w:r></w:p></w:tc>
            </w:tr>
            <w:tr>
                <w:tc><w:p><w:r><w:t>1-bosqich</w:t></w:r></w:p></w:tc>
                <w:tc><w:p><w:r><w:t>2026-yil</w:t></w:r></w:p></w:tc>
            </w:tr>
        </w:tbl>
    </w:body>
</w:document>`

	if _, err := w.Write([]byte(mockXML)); err != nil {
		t.Fatalf("failed to write XML: %v", err)
	}
	if err := zw.Close(); err != nil {
		t.Fatalf("failed to close zip: %v", err)
	}

	text, err := ExtractDocxContent(buf.Bytes())
	if err != nil {
		t.Fatalf("unexpected error parsing docx: %v", err)
	}

	if !strings.Contains(text, "Loyiha hisoboti va rejalari") {
		t.Errorf("missing paragraph text in docx output: %s", text)
	}
	if !strings.Contains(text, "| Bosqich | Muddat |") {
		t.Errorf("missing table row in docx output: %s", text)
	}
}

func TestExtractCSVContent(t *testing.T) {
	csvData := []byte("Mahsulot,Narx,Miqdor\nOlma,15000,5\nNok,25000,2\n")
	md, err := ExtractCSVContent(csvData)
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}

	if !strings.Contains(md, "| Mahsulot | Narx | Miqdor |") {
		t.Errorf("expected header row, got: %s", md)
	}
	if !strings.Contains(md, "| Olma | 15000 | 5 |") {
		t.Errorf("expected data row, got: %s", md)
	}
}

func TestChunkDocument(t *testing.T) {
	shortText := "Bu qisqa matn bo'lib, bo'linishi shart emas."
	chunks := ChunkDocument(shortText, 500, 100)
	if len(chunks) != 1 {
		t.Errorf("expected 1 chunk, got %d", len(chunks))
	}

	longText := strings.Repeat("Flutter va Go backend integratsiyasi a'lo darajada ishlaydi. ", 100)
	chunksLong := ChunkDocument(longText, 300, 50)
	if len(chunksLong) <= 1 {
		t.Errorf("expected multiple chunks, got %d", len(chunksLong))
	}
}

func TestExtractPDFContent_Uncompressed(t *testing.T) {
	pdf := []byte("%PDF-1.4\n1 0 obj\n<< /Length 50 >>\nstream\nBT\n/F1 12 Tf\n(Moliyaviy hisobot 2026) Tj\nET\nendstream\nendobj\nxref\ntrailer\n<< /Root 1 0 R >>\n%%EOF")
	fullText, pages, err := ExtractPDFContent(pdf)
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if !strings.Contains(fullText, "Moliyaviy hisobot 2026") {
		t.Errorf("expected text in pdf output, got: %s", fullText)
	}
	if len(pages) == 0 {
		t.Errorf("expected at least 1 page")
	}
}

func TestExtractPDFContent_FlateCompressed(t *testing.T) {
	rawContent := []byte("BT\n/F1 14 Tf\n10 10 Td\n(Kompaniya balansi: 50,000,000 UZS) Tj\nT*\n[(Sana: ) -200 (16.10.2026)] TJ\nET")
	var zlibBuf bytes.Buffer
	zw := zlib.NewWriter(&zlibBuf)
	_, _ = zw.Write(rawContent)
	_ = zw.Close()

	streamBytes := zlibBuf.Bytes()
	header := fmt.Sprintf("%%PDF-1.5\n1 0 obj\n<< /Filter /FlateDecode /Length %d >>\nstream\r\n", len(streamBytes))
	trailer := "\r\nendstream\nendobj\nxref\ntrailer\n<< /Root 1 0 R >>\n%%EOF"

	var mockPDF bytes.Buffer
	mockPDF.WriteString(header)
	mockPDF.Write(streamBytes)
	mockPDF.WriteString(trailer)

	fullText, pages, err := ExtractPDFContent(mockPDF.Bytes())
	if err != nil {
		t.Fatalf("unexpected error extracting compressed pdf: %v", err)
	}
	if !strings.Contains(fullText, "Kompaniya balansi: 50,000,000 UZS") {
		t.Errorf("expected decompressed text in pdf, got: %s", fullText)
	}
	if !strings.Contains(fullText, "16.10.2026") {
		t.Errorf("expected date from TJ array, got: %s", fullText)
	}
	if len(pages) != 1 {
		t.Errorf("expected 1 page, got %d", len(pages))
	}
}

func TestChunkDocumentPages(t *testing.T) {
	pages := []string{
		"[Sahifa 1]\nDaromadlar va Xarajatlar\n2026-yil 1-chorak daromad 120M UZS.",
		"[Sahifa 2]\nXulosa va Tavsiyalar\nBarcha rejalar muvaffaqiyatli bajarildi.",
	}
	chunks := ChunkDocumentPages(pages, 1000, 100)
	if len(chunks) != 2 {
		t.Fatalf("expected 2 chunks, got %d", len(chunks))
	}
	if chunks[0].PageNumber != 1 {
		t.Errorf("expected chunk 0 to be on page 1, got %d", chunks[0].PageNumber)
	}
	if chunks[1].PageNumber != 2 {
		t.Errorf("expected chunk 1 to be on page 2, got %d", chunks[1].PageNumber)
	}
	if chunks[0].SectionTitle != "Daromadlar va Xarajatlar" {
		t.Errorf("expected section title 'Daromadlar va Xarajatlar', got: %s", chunks[0].SectionTitle)
	}
}

func TestDetectFileTypeAndValidate_XLSX_PPTX_JSON(t *testing.T) {
	// XLSX
	ft, mime, err := DetectFileTypeAndValidate([]byte("PK\x03\x04\x14\x00\x06\x00"), "budget.xlsx")
	if err != nil || ft != FileTypeXLSX || mime != "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet" {
		t.Errorf("XLSX detection failed: ft=%v, mime=%v, err=%v", ft, mime, err)
	}

	// PPTX
	ft, mime, err = DetectFileTypeAndValidate([]byte("PK\x03\x04\x14\x00\x06\x00"), "pitch.pptx")
	if err != nil || ft != FileTypePPTX || mime != "application/vnd.openxmlformats-officedocument.presentationml.presentation" {
		t.Errorf("PPTX detection failed: ft=%v, mime=%v, err=%v", ft, mime, err)
	}

	// JSON
	ft, mime, err = DetectFileTypeAndValidate([]byte("{\n  \"status\": \"ok\",\n  \"count\": 42\n}"), "data.json")
	if err != nil || ft != FileTypeText || mime != "application/json" {
		t.Errorf("JSON detection failed: ft=%v, mime=%v, err=%v", ft, mime, err)
	}
}

func TestExtractXLSXContent(t *testing.T) {
	var buf bytes.Buffer
	zw := zip.NewWriter(&buf)

	// Workbook
	wbF, _ := zw.Create("xl/workbook.xml")
	_, _ = wbF.Write([]byte(`<?xml version="1.0" encoding="UTF-8"?>
<workbook xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">
  <sheets>
    <sheet name="Moliyaviy Hisobot" sheetId="1" id="rId1"/>
  </sheets>
</workbook>`))

	// Shared Strings
	ssF, _ := zw.Create("xl/sharedStrings.xml")
	_, _ = ssF.Write([]byte(`<?xml version="1.0" encoding="UTF-8"?>
<sst xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">
  <si><t>Daromad</t></si>
  <si><t>Xarajat</t></si>
</sst>`))

	// Sheet 1
	shF, _ := zw.Create("xl/worksheets/sheet1.xml")
	_, _ = shF.Write([]byte(`<?xml version="1.0" encoding="UTF-8"?>
<worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">
  <sheetData>
    <row r="1">
      <c r="A1" t="s"><v>0</v></c>
      <c r="B1"><v>15000000</v></c>
    </row>
    <row r="2">
      <c r="A2" t="s"><v>1</v></c>
      <c r="B2"><v>5000000</v></c>
    </row>
    <row r="3">
      <c r="A3"><v>Jami</v></c>
      <c r="B3"><f>SUM(B1:B2)</f><v>20000000</v></c>
    </row>
  </sheetData>
</worksheet>`))

	_ = zw.Close()

	fullText, sheets, err := ExtractXLSXContent(buf.Bytes())
	if err != nil {
		t.Fatalf("unexpected error parsing XLSX: %v", err)
	}

	if len(sheets) != 1 {
		t.Fatalf("expected 1 sheet, got %d", len(sheets))
	}
	if !strings.Contains(fullText, "Moliyaviy Hisobot") {
		t.Errorf("expected sheet name 'Moliyaviy Hisobot', got: %s", fullText)
	}
	if !strings.Contains(fullText, "A1: Daromad") {
		t.Errorf("expected 'A1: Daromad', got: %s", fullText)
	}
	if !strings.Contains(fullText, "SUM(B1:B2)") {
		t.Errorf("expected formula 'SUM(B1:B2)' preserved, got: %s", fullText)
	}
	if !strings.Contains(fullText, "20000000") {
		t.Errorf("expected computed value 20000000, got: %s", fullText)
	}
}

func TestExtractPPTXContent(t *testing.T) {
	var buf bytes.Buffer
	zw := zip.NewWriter(&buf)

	// Slide 1
	s1F, _ := zw.Create("ppt/slides/slide1.xml")
	_, _ = s1F.Write([]byte(`<?xml version="1.0" encoding="UTF-8"?>
<p:sld xmlns:p="http://schemas.openxmlformats.org/presentationml/2006/main" xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main">
  <p:cSld>
    <p:spTree>
      <p:sp>
        <p:txBody>
          <a:p><a:r><a:t>Antigravity AI Loyihasi</a:t></a:r></a:p>
          <a:p><a:r><a:t>2026-yilgi strategik reja va maqsadlar.</a:t></a:r></a:p>
        </p:txBody>
      </p:sp>
    </p:spTree>
  </p:cSld>
</p:sld>`))

	// Slide 2
	s2F, _ := zw.Create("ppt/slides/slide2.xml")
	_, _ = s2F.Write([]byte(`<?xml version="1.0" encoding="UTF-8"?>
<p:sld xmlns:p="http://schemas.openxmlformats.org/presentationml/2006/main" xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main">
  <p:cSld>
    <p:spTree>
      <p:sp>
        <p:txBody>
          <a:p><a:r><a:t>Texnologik Stek</a:t></a:r></a:p>
          <a:p><a:r><a:t>Flutter + Go + PostgreSQL arxitekturasi.</a:t></a:r></a:p>
        </p:txBody>
      </p:sp>
    </p:spTree>
  </p:cSld>
</p:sld>`))

	_ = zw.Close()

	fullText, slides, err := ExtractPPTXContent(buf.Bytes())
	if err != nil {
		t.Fatalf("unexpected error parsing PPTX: %v", err)
	}

	if len(slides) != 2 {
		t.Fatalf("expected 2 slides, got %d", len(slides))
	}
	if !strings.Contains(fullText, "[Slayd 1]") || !strings.Contains(fullText, "Antigravity AI Loyihasi") {
		t.Errorf("expected Slide 1 content, got: %s", fullText)
	}
	if !strings.Contains(fullText, "[Slayd 2]") || !strings.Contains(fullText, "Flutter + Go + PostgreSQL") {
		t.Errorf("expected Slide 2 content, got: %s", fullText)
	}
}

func TestExtractJSONContent(t *testing.T) {
	rawJSON := []byte(`{"project":"Go-getters","metrics":{"fps":120,"active_users":5000}}`)
	formatted, err := ExtractJSONContent(rawJSON)
	if err != nil {
		t.Fatalf("unexpected error formatting JSON: %v", err)
	}
	if !strings.Contains(formatted, "  \"project\": \"Go-getters\"") {
		t.Errorf("expected indented json, got: %s", formatted)
	}
}

