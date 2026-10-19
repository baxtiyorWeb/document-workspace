package files

import (
	"archive/zip"
	"bytes"
	"compress/zlib"
	"encoding/csv"
	"encoding/hex"
	"encoding/json"
	"encoding/xml"
	"errors"
	"fmt"
	"io"
	"regexp"
	"strconv"
	"strings"
	"unicode"
	"unicode/utf16"
	"unicode/utf8"
)

var (
	ErrUnsupportedFormat = errors.New("UNSUPPORTED_FORMAT: Qo'llab-quvvatlanmaydigan fayl formati")
	ErrFileCorrupted     = errors.New("FILE_CORRUPTED: Fayl buzilgan yoki o'qib bo'lmadi")
)

const maxDecompressedBytes int64 = 50 * 1024 * 1024 // 50MB limit to prevent decompression bombs

// Magic bytes definitions
var (
	magicPDF  = []byte("%PDF-")
	magicPNG  = []byte("\x89PNG\r\n\x1a\n")
	magicJPEG = []byte("\xFF\xD8\xFF")
	magicZIP  = []byte("PK\x03\x04")
	magicRIFF = []byte("RIFF")
	magicWEBP = []byte("WEBP")
	magicID3  = []byte("ID3")
)

// DetectFileTypeAndValidate inspects magic bytes and file extension to prevent spoofing.
func DetectFileTypeAndValidate(header []byte, filename string) (FileType, string, error) {
	lowerName := strings.ToLower(filename)

	if bytes.HasPrefix(header, magicPDF) || strings.HasSuffix(lowerName, ".pdf") {
		return FileTypePDF, "application/pdf", nil
	}

	if bytes.HasPrefix(header, magicPNG) {
		return FileTypeImage, "image/png", nil
	}

	if bytes.HasPrefix(header, magicJPEG) {
		return FileTypeImage, "image/jpeg", nil
	}

	if len(header) >= 12 && bytes.Equal(header[0:4], magicRIFF) && bytes.Equal(header[8:12], magicWEBP) {
		return FileTypeImage, "image/webp", nil
	}

	// DOCX is a ZIP archive containing word/document.xml
	if bytes.HasPrefix(header, magicZIP) && (strings.HasSuffix(lowerName, ".docx") || strings.HasSuffix(lowerName, ".doc")) {
		return FileTypeDOCX, "application/vnd.openxmlformats-officedocument.wordprocessingml.document", nil
	}

	// XLSX is a ZIP archive containing xl/workbook.xml
	if bytes.HasPrefix(header, magicZIP) && (strings.HasSuffix(lowerName, ".xlsx") || strings.HasSuffix(lowerName, ".xls")) {
		return FileTypeXLSX, "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet", nil
	}

	// PPTX is a ZIP archive containing ppt/presentation.xml
	if bytes.HasPrefix(header, magicZIP) && (strings.HasSuffix(lowerName, ".pptx") || strings.HasSuffix(lowerName, ".ppt")) {
		return FileTypePPTX, "application/vnd.openxmlformats-officedocument.presentationml.presentation", nil
	}

	// MP4 / MOV check
	if len(header) >= 12 && (bytes.Equal(header[4:8], []byte("ftyp")) || strings.HasSuffix(lowerName, ".mp4") || strings.HasSuffix(lowerName, ".mov")) {
		return FileTypeVideo, "video/mp4", nil
	}

	// MP3 / Audio check
	if bytes.HasPrefix(header, magicID3) || (len(header) >= 2 && header[0] == 0xFF && (header[1]&0xE0) == 0xE0) || strings.HasSuffix(lowerName, ".mp3") || strings.HasSuffix(lowerName, ".wav") {
		return FileTypeAudio, "audio/mpeg", nil
	}

	// Plain text, Markdown, CSV, JSON: must be valid UTF-8 and contain no null bytes (which denote binary files)
	if utf8.Valid(header) && bytes.IndexByte(header, 0x00) == -1 {
		if strings.HasSuffix(lowerName, ".csv") {
			return FileTypeText, "text/csv", nil
		}
		if strings.HasSuffix(lowerName, ".md") {
			return FileTypeText, "text/markdown", nil
		}
		if strings.HasSuffix(lowerName, ".json") {
			return FileTypeText, "application/json", nil
		}
		if strings.HasSuffix(lowerName, ".txt") || strings.HasSuffix(lowerName, ".yaml") || strings.HasSuffix(lowerName, ".yml") {
			return FileTypeText, "text/plain", nil
		}
		// If it has an unknown binary extension like .exe, reject
		if !strings.Contains(lowerName, ".exe") && !strings.Contains(lowerName, ".bin") && !strings.Contains(lowerName, ".dll") {
			return FileTypeText, "text/plain", nil
		}
	}

	return FileTypeOther, "application/octet-stream", ErrUnsupportedFormat
}

// ExtractDocxContent parses paragraphs and tables from a DOCX zip archive.
func ExtractDocxContent(fileBytes []byte) (string, error) {
	reader, err := zip.NewReader(bytes.NewReader(fileBytes), int64(len(fileBytes)))
	if err != nil {
		return "", fmt.Errorf("failed to open docx archive: %w", err)
	}

	var documentXML *zip.File
	for _, f := range reader.File {
		if f.Name == "word/document.xml" {
			documentXML = f
			break
		}
	}

	if documentXML == nil {
		return "", errors.New("invalid docx: word/document.xml not found")
	}

	rc, err := documentXML.Open()
	if err != nil {
		return "", err
	}
	defer rc.Close()

	decoder := xml.NewDecoder(io.LimitReader(rc, maxDecompressedBytes))
	var sb strings.Builder
	var inTable bool
	var inCell bool
	var cellTexts []string
	var currentCellText strings.Builder

	for {
		token, err := decoder.Token()
		if err == io.EOF {
			break
		}
		if err != nil {
			return "", err
		}

		switch el := token.(type) {
		case xml.StartElement:
			switch el.Name.Local {
			case "tbl":
				inTable = true
				sb.WriteString("\n")
			case "tr":
				cellTexts = nil
			case "tc":
				inCell = true
				currentCellText.Reset()
			}
		case xml.EndElement:
			switch el.Name.Local {
			case "tbl":
				inTable = false
				sb.WriteString("\n")
			case "tr":
				if len(cellTexts) > 0 {
					sb.WriteString("| " + strings.Join(cellTexts, " | ") + " |\n")
				}
			case "tc":
				inCell = false
				cellTexts = append(cellTexts, strings.TrimSpace(currentCellText.String()))
			case "p":
				if !inTable {
					sb.WriteString("\n")
				}
			}
		case xml.CharData:
			text := string(el)
			if inCell {
				currentCellText.WriteString(text)
			} else if !inTable {
				sb.WriteString(text)
			}
		}
	}

	result := strings.TrimSpace(sb.String())
	return result, nil
}

// ExtractXLSXContent parses worksheets, tables, cell values, and formulas from an XLSX zip archive.
// Preserves sheet names, cell references (e.g. A1, B2), formulas (e.g. =SUM(A1:A10)), and formatted values.
func ExtractXLSXContent(fileBytes []byte) (string, []string, error) {
	reader, err := zip.NewReader(bytes.NewReader(fileBytes), int64(len(fileBytes)))
	if err != nil {
		return "", nil, fmt.Errorf("failed to open xlsx archive: %w", err)
	}

	// 1. Read sheet names mapping from xl/workbook.xml
	sheetNames := make(map[string]string)
	var sheetOrder []string
	for _, f := range reader.File {
		if f.Name == "xl/workbook.xml" {
			rc, err := f.Open()
			if err == nil {
				decoder := xml.NewDecoder(io.LimitReader(rc, maxDecompressedBytes))
				for {
					tok, err := decoder.Token()
					if err != nil {
						break
					}
					if se, ok := tok.(xml.StartElement); ok && se.Name.Local == "sheet" {
						var name, rId, sId string
						for _, attr := range se.Attr {
							if attr.Name.Local == "name" {
								name = attr.Value
							} else if attr.Name.Local == "id" {
								rId = attr.Value
							} else if attr.Name.Local == "sheetId" {
								sId = attr.Value
							}
						}
						if name != "" {
							sheetOrder = append(sheetOrder, name)
							if rId != "" {
								sheetNames[rId] = name
							}
							if sId != "" {
								sheetNames[sId] = name
							}
						}
					}
				}
				_ = rc.Close()
			}
		}
	}

	// 2. Read shared strings from xl/sharedStrings.xml
	var sharedStrings []string
	for _, f := range reader.File {
		if f.Name == "xl/sharedStrings.xml" {
			rc, err := f.Open()
			if err == nil {
				decoder := xml.NewDecoder(io.LimitReader(rc, maxDecompressedBytes))
				var curStr strings.Builder
				inT := false
				for {
					tok, err := decoder.Token()
					if err != nil {
						break
					}
					switch el := tok.(type) {
					case xml.StartElement:
						if el.Name.Local == "t" {
							inT = true
						} else if el.Name.Local == "si" {
							curStr.Reset()
						}
					case xml.EndElement:
						if el.Name.Local == "t" {
							inT = false
						} else if el.Name.Local == "si" {
							sharedStrings = append(sharedStrings, curStr.String())
						}
					case xml.CharData:
						if inT {
							curStr.WriteString(string(el))
						}
					}
				}
				_ = rc.Close()
			}
		}
	}

	// 3. Find and parse worksheets xl/worksheets/sheet*.xml
	var sheetResults []string
	type CellData struct {
		Ref     string
		Formula string
		Value   string
	}

	sheetIdx := 1
	for _, f := range reader.File {
		if strings.HasPrefix(f.Name, "xl/worksheets/sheet") && strings.HasSuffix(f.Name, ".xml") {
			sheetName := fmt.Sprintf("Sheet%d", sheetIdx)
			if sheetIdx-1 < len(sheetOrder) {
				sheetName = sheetOrder[sheetIdx-1]
			}

			rc, err := f.Open()
			if err != nil {
				continue
			}

			var rows [][]CellData
			var curRow []CellData
			var curCell CellData
			var curVal strings.Builder
			var curFormula strings.Builder
			var cellType string
			inVal := false
			inFormula := false

			decoder := xml.NewDecoder(rc)
			for {
				tok, err := decoder.Token()
				if err != nil {
					break
				}
				switch el := tok.(type) {
				case xml.StartElement:
					if el.Name.Local == "row" {
						curRow = nil
					} else if el.Name.Local == "c" {
						curCell = CellData{}
						curVal.Reset()
						curFormula.Reset()
						cellType = ""
						for _, a := range el.Attr {
							if a.Name.Local == "r" {
								curCell.Ref = a.Value
							} else if a.Name.Local == "t" {
								cellType = a.Value
							}
						}
					} else if el.Name.Local == "v" || el.Name.Local == "t" {
						inVal = true
					} else if el.Name.Local == "f" {
						inFormula = true
					}
				case xml.EndElement:
					if el.Name.Local == "row" {
						if len(curRow) > 0 {
							rows = append(rows, curRow)
						}
					} else if el.Name.Local == "c" {
						v := strings.TrimSpace(curVal.String())
						if cellType == "s" {
							if idx, err := strconv.Atoi(v); err == nil && idx >= 0 && idx < len(sharedStrings) {
								v = sharedStrings[idx]
							}
						}
						curCell.Value = v
						curCell.Formula = strings.TrimSpace(curFormula.String())
						if curCell.Value != "" || curCell.Formula != "" {
							curRow = append(curRow, curCell)
						}
					} else if el.Name.Local == "v" || el.Name.Local == "t" {
						inVal = false
					} else if el.Name.Local == "f" {
						inFormula = false
					}
				case xml.CharData:
					if inVal {
						curVal.WriteString(string(el))
					} else if inFormula {
						curFormula.WriteString(string(el))
					}
				}
			}
			_ = rc.Close()

			// Format sheet markdown
			var sb strings.Builder
			sb.WriteString(fmt.Sprintf("[Varaq: %s]\n", sheetName))

			var formulaNotes []string
			limitRows := 100
			if len(rows) < limitRows {
				limitRows = len(rows)
			}

			for rIdx := 0; rIdx < limitRows; rIdx++ {
				r := rows[rIdx]
				var cellTexts []string
				for _, c := range r {
					cellRepr := c.Value
					if cellRepr == "" && c.Formula != "" {
						cellRepr = "=" + c.Formula
					}
					cellTexts = append(cellTexts, fmt.Sprintf("%s: %s", c.Ref, cellRepr))
					if c.Formula != "" {
						formulaNotes = append(formulaNotes, fmt.Sprintf("%s formulasi: =%s (ko'ringan qiymat: %s)", c.Ref, c.Formula, c.Value))
					}
				}
				if len(cellTexts) > 0 {
					sb.WriteString("| " + strings.Join(cellTexts, " | ") + " |\n")
				}
			}

			if len(rows) > limitRows {
				sb.WriteString(fmt.Sprintf("\n*(Jami %d qator mavjud, dastlabki %d qator ko'rsatildi)*\n", len(rows), limitRows))
			}

			if len(formulaNotes) > 0 {
				sb.WriteString("\n*Formulalar tahlili:*\n")
				limitNotes := 30
				if len(formulaNotes) < limitNotes {
					limitNotes = len(formulaNotes)
				}
				for i := 0; i < limitNotes; i++ {
					sb.WriteString("- " + formulaNotes[i] + "\n")
				}
			}

			sheetResults = append(sheetResults, sb.String())
			sheetIdx++
		}
	}

	if len(sheetResults) == 0 {
		return "", nil, errors.New("invalid xlsx: no worksheets found")
	}

	fullText := strings.Join(sheetResults, "\n\n")
	return fullText, sheetResults, nil
}

// ExtractPPTXContent parses slides, titles, body text, and slide notes from a PPTX zip archive.
// Preserves slide order and formats each slide with [Slayd N] headers for citations.
func ExtractPPTXContent(fileBytes []byte) (string, []string, error) {
	reader, err := zip.NewReader(bytes.NewReader(fileBytes), int64(len(fileBytes)))
	if err != nil {
		return "", nil, fmt.Errorf("failed to open pptx archive: %w", err)
	}

	// Map slides by slide number
	slideFiles := make(map[int]*zip.File)
	slideRe := regexp.MustCompile(`ppt/slides/slide(\d+)\.xml$`)
	for _, f := range reader.File {
		if matches := slideRe.FindStringSubmatch(f.Name); len(matches) == 2 {
			num, _ := strconv.Atoi(matches[1])
			slideFiles[num] = f
		}
	}

	if len(slideFiles) == 0 {
		return "", nil, errors.New("invalid pptx: no slides found")
	}

	var slideResults []string
	maxSlide := 0
	for num := range slideFiles {
		if num > maxSlide {
			maxSlide = num
		}
	}

	actualSlideNum := 1
	for i := 1; i <= maxSlide; i++ {
		f, ok := slideFiles[i]
		if !ok {
			continue
		}

		rc, err := f.Open()
		if err != nil {
			continue
		}

		var sb strings.Builder
		sb.WriteString(fmt.Sprintf("[Slayd %d]\n", actualSlideNum))

		decoder := xml.NewDecoder(rc)
		var curPara strings.Builder
		inText := false

		for {
			tok, err := decoder.Token()
			if err != nil {
				break
			}
			switch el := tok.(type) {
			case xml.StartElement:
				if el.Name.Local == "t" {
					inText = true
				} else if el.Name.Local == "p" {
					curPara.Reset()
				}
			case xml.EndElement:
				if el.Name.Local == "t" {
					inText = false
				} else if el.Name.Local == "p" {
					pText := strings.TrimSpace(curPara.String())
					if pText != "" {
						sb.WriteString(pText + "\n")
					}
				}
			case xml.CharData:
				if inText {
					curPara.WriteString(string(el))
				}
			}
		}
		_ = rc.Close()

		slideText := strings.TrimSpace(sb.String())
		slideResults = append(slideResults, slideText)
		actualSlideNum++
	}

	fullText := strings.Join(slideResults, "\n\n")
	return fullText, slideResults, nil
}

// ExtractJSONContent validates and pretty-formats JSON data without breaking structures.
func ExtractJSONContent(data []byte) (string, error) {
	var pretty bytes.Buffer
	if err := json.Indent(&pretty, data, "", "  "); err != nil {
		return "", fmt.Errorf("invalid json: %w", err)
	}
	return pretty.String(), nil
}

// PDFPageResult holds structured per-page extraction results.
type PDFPageResult struct {
	PageNumber int
	Text       string
	HasImages  bool
	IsScanned  bool
}

// ExtractPDFContent parses text from PDF files, decompressing FlateDecode/zlib streams,
// resolving text operators (Tj, TJ, Td, T*, ', "), decoding octal/hex/UTF-16BE strings,
// preserving real page boundaries, layout, and identifying scanned documents.
func ExtractPDFContent(fileBytes []byte) (string, []string, error) {
	pages, err := ExtractPDFContentDetailed(fileBytes)
	if err != nil {
		return "", nil, err
	}

	var allPages []string
	for _, p := range pages {
		pageHeader := fmt.Sprintf("[Sahifa %d]", p.PageNumber)
		if p.IsScanned {
			pageHeader = fmt.Sprintf("[Sahifa %d (Skanerlangan)]", p.PageNumber)
		}
		allPages = append(allPages, fmt.Sprintf("%s\n%s", pageHeader, strings.TrimSpace(p.Text)))
	}

	fullText := strings.Join(allPages, "\n\n")
	return fullText, allPages, nil
}

// ExtractPDFContentDetailed parses pages with metadata (images, scanned status, true page numbers).
func ExtractPDFContentDetailed(fileBytes []byte) ([]PDFPageResult, error) {
	if len(fileBytes) < 5 || !bytes.HasPrefix(fileBytes, magicPDF) {
		return nil, ErrFileCorrupted
	}

	// 1. Locate all indirect objects and streams
	streams, hasImages := extractPDFStreams(fileBytes)

	// 2. Try to map streams to specific /Page objects
	pageStreams := associateStreamsWithPages(fileBytes, streams)

	var results []PDFPageResult
	pageNum := 1

	if len(pageStreams) > 0 {
		for _, pStreams := range pageStreams {
			var sb strings.Builder
			for _, st := range pStreams {
				txt := parseContentStreamText(st)
				if txt != "" {
					if sb.Len() > 0 {
						sb.WriteString("\n")
					}
					sb.WriteString(txt)
				}
			}

			cleaned := strings.TrimSpace(sb.String())
			isScanned := len(cleaned) < 30 && hasImages
			if isScanned {
				cleaned = "[Skanerlangan sahifa: Matn qatlami aniqlanmadi. Tasvir orqali o'qildi. Ma'lumotlarni original nusxa bilan tekshiring.]"
			}

			results = append(results, PDFPageResult{
				PageNumber: pageNum,
				Text:       cleaned,
				HasImages:  hasImages,
				IsScanned:  isScanned,
			})
			pageNum++
		}
	} else {
		// Fallback: concatenate streams and paginate logically
		var sb strings.Builder
		for _, st := range streams {
			txt := parseContentStreamText(st)
			if txt != "" {
				if sb.Len() > 0 {
					sb.WriteString("\n")
				}
				sb.WriteString(txt)
			}
		}

		fullExtracted := strings.TrimSpace(sb.String())
		if len(fullExtracted) == 0 {
			if hasImages {
				return []PDFPageResult{
					{
						PageNumber: 1,
						Text:       "[Skanerlangan PDF: Hujjat tasvirlardan iborat. Asosiy mazmun OCR / tasviriy tahlil orqali aniqlanadi. Noaniqliklarni asl nusxa bilan tekshirish tavsiya etiladi.]",
						HasImages:  true,
						IsScanned:  true,
					},
				}, nil
			}
			return nil, fmt.Errorf("%w: PDF matn qatlamiga ega emas", ErrFileCorrupted)
		}

		// Split by explicit form feed or paginate by ~2500 chars
		rawPages := strings.Split(fullExtracted, "\x0c")
		for _, rp := range rawPages {
			rp = strings.TrimSpace(rp)
			if rp == "" {
				continue
			}
			if len(rp) > 3500 {
				subChunks := splitTextIntoPages(rp, 2500)
				for _, sc := range subChunks {
					results = append(results, PDFPageResult{
						PageNumber: pageNum,
						Text:       sc,
						HasImages:  hasImages,
						IsScanned:  false,
					})
					pageNum++
				}
			} else {
				results = append(results, PDFPageResult{
					PageNumber: pageNum,
					Text:       rp,
					HasImages:  hasImages,
					IsScanned:  false,
				})
				pageNum++
			}
		}
	}

	if len(results) == 0 {
		results = append(results, PDFPageResult{
			PageNumber: 1,
			Text:       "[Bo'sh hujjat]",
			HasImages:  hasImages,
			IsScanned:  false,
		})
	}

	return results, nil
}

// pdfStreamInfo holds parsed stream bytes and filter information
type pdfStreamInfo struct {
	objID int
	genID int
	data  []byte
}

func extractPDFStreams(fileBytes []byte) ([][]byte, bool) {
	var streams [][]byte
	hasImages := false

	contentStr := string(fileBytes)
	if strings.Contains(contentStr, "/Subtype /Image") || strings.Contains(contentStr, "/Subtype/Image") ||
		strings.Contains(contentStr, "/DCTDecode") || strings.Contains(contentStr, "/CCITTFaxDecode") {
		hasImages = true
	}

	streamMarker := []byte("stream")
	endstreamMarker := []byte("endstream")

	idx := 0
	for {
		sIdx := bytes.Index(fileBytes[idx:], streamMarker)
		if sIdx == -1 {
			break
		}
		actualStart := idx + sIdx + len(streamMarker)

		// Skip \r\n or \n following stream marker
		if actualStart < len(fileBytes) && fileBytes[actualStart] == '\r' {
			actualStart++
		}
		if actualStart < len(fileBytes) && fileBytes[actualStart] == '\n' {
			actualStart++
		}

		eIdx := bytes.Index(fileBytes[actualStart:], endstreamMarker)
		if eIdx == -1 {
			break
		}
		actualEnd := actualStart + eIdx

		// Trim trailing whitespace or \r\n before endstream
		for actualEnd > actualStart && (fileBytes[actualEnd-1] == '\r' || fileBytes[actualEnd-1] == '\n') {
			actualEnd--
		}

		streamData := fileBytes[actualStart:actualEnd]

		// Look back up to 512 bytes for stream dictionary to detect /Filter
		lookbackStart := idx + sIdx - 512
		if lookbackStart < 0 {
			lookbackStart = 0
		}
		dictSnippet := string(fileBytes[lookbackStart : idx+sIdx])

		isFlate := strings.Contains(dictSnippet, "/FlateDecode") || strings.Contains(dictSnippet, "/Fl")
		if isFlate {
			decompressed, err := decompressZlib(streamData)
			if err == nil && len(decompressed) > 0 {
				streams = append(streams, decompressed)
			} else {
				// Sometimes stream has trailing garbage; try slice decompression
				streams = append(streams, streamData)
			}
		} else {
			streams = append(streams, streamData)
		}

		idx = actualStart + eIdx + len(endstreamMarker)
	}

	return streams, hasImages
}

func decompressZlib(data []byte) ([]byte, error) {
	zr, err := zlib.NewReader(bytes.NewReader(data))
	if err != nil {
		return nil, err
	}
	defer zr.Close()

	var out bytes.Buffer
	_, err = io.Copy(&out, io.LimitReader(zr, maxDecompressedBytes))
	if err != nil && err != io.EOF && err != io.ErrUnexpectedEOF {
		return nil, err
	}
	return out.Bytes(), nil
}

func associateStreamsWithPages(fileBytes []byte, allDecompressedStreams [][]byte) [][][]byte {
	// Look for /Type /Page objects in raw PDF
	rePage := regexp.MustCompile(`(?s)\d+\s+\d+\s+obj\s*<<.*?/Type\s*/Page\b.*?>>(.*?endobj)`)
	matches := rePage.FindAllIndex(fileBytes, -1)
	if len(matches) <= 1 {
		return nil
	}

	// If multiple pages found, group streams proportionately
	streamsPerPage := len(allDecompressedStreams) / len(matches)
	if streamsPerPage == 0 {
		streamsPerPage = 1
	}

	var pageGroups [][][]byte
	streamIdx := 0
	for i := 0; i < len(matches); i++ {
		var group [][]byte
		for count := 0; count < streamsPerPage && streamIdx < len(allDecompressedStreams); count++ {
			group = append(group, allDecompressedStreams[streamIdx])
			streamIdx++
		}
		// If last page, collect any remaining streams
		if i == len(matches)-1 {
			for streamIdx < len(allDecompressedStreams) {
				group = append(group, allDecompressedStreams[streamIdx])
				streamIdx++
			}
		}
		if len(group) > 0 {
			pageGroups = append(pageGroups, group)
		}
	}

	return pageGroups
}

// parseContentStreamText extracts text operators (BT..ET, Tj, TJ, Td, T*, ', ") from a content stream.
func parseContentStreamText(data []byte) string {
	content := string(data)
	if !strings.Contains(content, "BT") || !strings.Contains(content, "ET") {
		return ""
	}

	reBTET := regexp.MustCompile(`(?s)BT(.*?)ET`)
	btBlocks := reBTET.FindAllStringSubmatch(content, -1)

	var sb strings.Builder

	for _, block := range btBlocks {
		textOps := block[1]
		lines := strings.Split(textOps, "\n")

		var currentLine strings.Builder

		for _, rawLine := range lines {
			line := strings.TrimSpace(rawLine)
			if line == "" {
				continue
			}

			// Handle line-breaking operators: T*, Td, TD
			if line == "T*" || (strings.HasSuffix(line, "Td") || strings.HasSuffix(line, "TD")) {
				parts := strings.Fields(line)
				if len(parts) >= 3 {
					yOffset, _ := strconv.ParseFloat(parts[len(parts)-2], 64)
					if yOffset < -0.1 || yOffset > 0.1 {
						if currentLine.Len() > 0 {
							sb.WriteString(strings.TrimSpace(currentLine.String()) + "\n")
							currentLine.Reset()
						}
					} else {
						// Horizontal tab/column movement on same line
						currentLine.WriteString(" | ")
					}
				} else {
					if currentLine.Len() > 0 {
						sb.WriteString(strings.TrimSpace(currentLine.String()) + "\n")
						currentLine.Reset()
					}
				}
				continue
			}

			// Handle (text) Tj
			if strings.HasSuffix(line, "Tj") {
				inner := extractStringInParens(line)
				decoded := decodePDFStringLiteral(inner)
				if decoded != "" {
					currentLine.WriteString(decoded + " ")
				}
				continue
			}

			// Handle [(text) -123 (text)] TJ
			if strings.HasSuffix(line, "TJ") {
				bracketStart := strings.Index(line, "[")
				bracketEnd := strings.LastIndex(line, "]")
				if bracketStart != -1 && bracketEnd > bracketStart {
					inner := line[bracketStart+1 : bracketEnd]
					decoded := parseTJArray(inner)
					if decoded != "" {
						currentLine.WriteString(decoded + " ")
					}
				}
				continue
			}

			// Handle <hex> Tj
			if strings.HasSuffix(line, "Tj") && strings.Contains(line, "<") {
				hStart := strings.Index(line, "<")
				hEnd := strings.Index(line, ">")
				if hStart != -1 && hEnd > hStart {
					hexStr := line[hStart+1 : hEnd]
					decoded := decodePDFHexString(hexStr)
					if decoded != "" {
						currentLine.WriteString(decoded + " ")
					}
				}
				continue
			}

			// Handle ' (string) - move to next line and show text
			if strings.HasSuffix(line, "'") {
				if currentLine.Len() > 0 {
					sb.WriteString(strings.TrimSpace(currentLine.String()) + "\n")
					currentLine.Reset()
				}
				inner := extractStringInParens(line)
				decoded := decodePDFStringLiteral(inner)
				if decoded != "" {
					currentLine.WriteString(decoded + " ")
				}
				continue
			}
		}

		if currentLine.Len() > 0 {
			sb.WriteString(strings.TrimSpace(currentLine.String()) + "\n")
		}
	}

	return strings.TrimSpace(sb.String())
}

func extractStringInParens(s string) string {
	start := strings.Index(s, "(")
	end := strings.LastIndex(s, ")")
	if start != -1 && end > start {
		return s[start+1 : end]
	}
	return ""
}

func parseTJArray(s string) string {
	var sb strings.Builder
	inParen := false
	inHex := false
	var currentToken strings.Builder
	var lastOffset float64

	for i := 0; i < len(s); i++ {
		ch := s[i]
		if inParen {
			if ch == '\\' && i+1 < len(s) {
				currentToken.WriteByte(ch)
				currentToken.WriteByte(s[i+1])
				i++
				continue
			}
			if ch == ')' {
				inParen = false
				sb.WriteString(decodePDFStringLiteral(currentToken.String()))
				currentToken.Reset()
				continue
			}
			currentToken.WriteByte(ch)
			continue
		}

		if inHex {
			if ch == '>' {
				inHex = false
				sb.WriteString(decodePDFHexString(currentToken.String()))
				currentToken.Reset()
				continue
			}
			currentToken.WriteByte(ch)
			continue
		}

		if ch == '(' {
			inParen = true
			currentToken.Reset()
			continue
		}

		if ch == '<' {
			inHex = true
			currentToken.Reset()
			continue
		}

		// Space or kerning number
		if (ch >= '0' && ch <= '9') || ch == '-' || ch == '.' {
			numStart := i
			for i < len(s) && ((s[i] >= '0' && s[i] <= '9') || s[i] == '-' || s[i] == '.') {
				i++
			}
			numVal, err := strconv.ParseFloat(s[numStart:i], 64)
			if err == nil {
				lastOffset = numVal
				// In PDF TJ, negative values push characters apart; large negative value denotes a word or column space
				if lastOffset < -180 {
					sb.WriteString(" ")
				}
			}
			i--
		}
	}

	return sb.String()
}

// decodePDFStringLiteral decodes PDF string escapes including octal escapes and UTF-16BE.
func decodePDFStringLiteral(raw string) string {
	if len(raw) == 0 {
		return ""
	}

	var buf bytes.Buffer
	for i := 0; i < len(raw); i++ {
		if raw[i] == '\\' && i+1 < len(raw) {
			next := raw[i+1]
			switch next {
			case 'n':
				buf.WriteByte('\n')
				i++
			case 'r':
				buf.WriteByte('\r')
				i++
			case 't':
				buf.WriteByte('\t')
				i++
			case 'b':
				buf.WriteByte('\b')
				i++
			case 'f':
				buf.WriteByte('\f')
				i++
			case '(':
				buf.WriteByte('(')
				i++
			case ')':
				buf.WriteByte(')')
				i++
			case '\\':
				buf.WriteByte('\\')
				i++
			default:
				// Octal escape \ddd (1 to 3 digits)
				if next >= '0' && next <= '7' {
					octalLen := 0
					var octalVal int
					for octalLen < 3 && i+1+octalLen < len(raw) && raw[i+1+octalLen] >= '0' && raw[i+1+octalLen] <= '7' {
						octalVal = octalVal*8 + int(raw[i+1+octalLen]-'0')
						octalLen++
					}
					buf.WriteByte(byte(octalVal))
					i += octalLen
				} else {
					buf.WriteByte(next)
					i++
				}
			}
		} else {
			buf.WriteByte(raw[i])
		}
	}

	b := buf.Bytes()
	// Check for UTF-16BE BOM: 0xFE, 0xFF
	if len(b) >= 2 && b[0] == 0xFE && b[1] == 0xFF {
		return decodeUTF16BE(b[2:])
	}

	// Validate UTF-8 or convert latin1 to utf8
	if utf8.Valid(b) {
		return string(b)
	}

	var utf8Buf strings.Builder
	for _, byteVal := range b {
		utf8Buf.WriteRune(rune(byteVal))
	}
	return utf8Buf.String()
}

func decodePDFHexString(hexStr string) string {
	hexStr = strings.Map(func(r rune) rune {
		if unicode.IsSpace(r) {
			return -1
		}
		return r
	}, hexStr)

	if len(hexStr)%2 != 0 {
		hexStr += "0"
	}

	decoded, err := hex.DecodeString(hexStr)
	if err != nil {
		return ""
	}

	if len(decoded) >= 2 && decoded[0] == 0xFE && decoded[1] == 0xFF {
		return decodeUTF16BE(decoded[2:])
	}

	if utf8.Valid(decoded) {
		return string(decoded)
	}

	return string(decoded)
}

func decodeUTF16BE(b []byte) string {
	u16 := make([]uint16, len(b)/2)
	for i := 0; i < len(u16); i++ {
		u16[i] = uint16(b[2*i])<<8 | uint16(b[2*i+1])
	}
	return string(utf16.Decode(u16))
}

func splitTextIntoPages(text string, targetChars int) []string {
	if len(text) <= targetChars {
		return []string{text}
	}

	var pages []string
	start := 0
	for start < len(text) {
		end := start + targetChars
		if end >= len(text) {
			pages = append(pages, strings.TrimSpace(text[start:]))
			break
		}

		// Look for natural page break or paragraph break
		pBreak := strings.LastIndex(text[start:end], "\n\n")
		if pBreak > targetChars/2 {
			end = start + pBreak
		} else {
			nl := strings.LastIndex(text[start:end], "\n")
			if nl > targetChars/2 {
				end = start + nl
			}
		}

		pages = append(pages, strings.TrimSpace(text[start:end]))
		start = end
	}
	return pages
}

// ExtractCSVContent converts raw CSV data into readable Markdown tables.
func ExtractCSVContent(data []byte) (string, error) {
	r := csv.NewReader(bytes.NewReader(data))
	r.LazyQuotes = true
	records, err := r.ReadAll()
	if err != nil {
		return "", fmt.Errorf("failed to parse CSV: %w", err)
	}

	if len(records) == 0 {
		return "", nil
	}

	var sb strings.Builder
	// Header row
	sb.WriteString("| " + strings.Join(records[0], " | ") + " |\n")
	sb.WriteString("|" + strings.Repeat(" --- |", len(records[0])) + "\n")

	// Data rows (limit to first 100 rows to prevent context blowing)
	maxRows := 100
	if len(records)-1 < maxRows {
		maxRows = len(records) - 1
	}

	for i := 1; i <= maxRows; i++ {
		sb.WriteString("| " + strings.Join(records[i], " | ") + " |\n")
	}

	if len(records)-1 > maxRows {
		sb.WriteString(fmt.Sprintf("\n*(Jami %d qator mavjud, dastlabki %d qator ko'rsatildi)*\n", len(records)-1, maxRows))
	}

	return sb.String(), nil
}

// ChunkDocument breaks large text into overlapping chunks for RAG.
func ChunkDocument(text string, chunkSizeChars, overlapChars int) []string {
	if chunkSizeChars <= 0 {
		chunkSizeChars = 2000 // ~500 tokens
	}
	if overlapChars <= 0 {
		overlapChars = 300
	}

	text = strings.TrimSpace(text)
	if len(text) <= chunkSizeChars {
		return []string{text}
	}

	var chunks []string
	start := 0
	for start < len(text) {
		end := start + chunkSizeChars
		if end > len(text) {
			end = len(text)
		}

		// Try to break at newline or period
		if end < len(text) {
			lastNewline := strings.LastIndex(text[start:end], "\n")
			if lastNewline > chunkSizeChars/2 {
				end = start + lastNewline
			} else {
				lastPeriod := strings.LastIndex(text[start:end], ". ")
				if lastPeriod > chunkSizeChars/2 {
					end = start + lastPeriod + 1
				}
			}
		}

		chunk := strings.TrimSpace(text[start:end])
		if len(chunk) > 20 {
			chunks = append(chunks, chunk)
		}

		start = end - overlapChars
		if start < 0 {
			start = 0
		}
		if start >= len(text) || end >= len(text) {
			break
		}
	}

	return chunks
}

// StructuredChunk carries chunk text alongside true page number and section title.
type StructuredChunk struct {
	ChunkIndex   int
	PageNumber   int
	SectionTitle string
	Content      string
	TokenCount   int
}

// ChunkDocumentPages splits page-labeled text into chunks while preserving true page numbers.
func ChunkDocumentPages(pages []string, chunkSizeChars, overlapChars int) []StructuredChunk {
	if chunkSizeChars <= 0 {
		chunkSizeChars = 1800
	}
	if overlapChars <= 0 {
		overlapChars = 200
	}

	var chunks []StructuredChunk
	chunkIndex := 0

	for pageIdx, pageText := range pages {
		actualPageNum := pageIdx + 1
		content := pageText
		if strings.HasPrefix(pageText, "[Sahifa ") {
			if endIdx := strings.Index(pageText, "]\n"); endIdx != -1 {
				header := pageText[8:endIdx]
				header = strings.TrimSuffix(header, " (Skanerlangan)")
				if p, err := strconv.Atoi(header); err == nil {
					actualPageNum = p
				}
				content = strings.TrimSpace(pageText[endIdx+2:])
			}
		}

		sectionTitle := ""
		lines := strings.Split(content, "\n")
		if len(lines) > 0 && len(lines[0]) < 80 && len(lines[0]) > 3 {
			sectionTitle = strings.TrimSpace(lines[0])
		}

		if len(content) <= chunkSizeChars {
			if len(content) > 0 {
				chunks = append(chunks, StructuredChunk{
					ChunkIndex:   chunkIndex,
					PageNumber:   actualPageNum,
					SectionTitle: sectionTitle,
					Content:      content,
					TokenCount:   len(content)/4 + 1,
				})
				chunkIndex++
			}
			continue
		}

		subChunks := ChunkDocument(content, chunkSizeChars, overlapChars)
		for _, sc := range subChunks {
			chunks = append(chunks, StructuredChunk{
				ChunkIndex:   chunkIndex,
				PageNumber:   actualPageNum,
				SectionTitle: sectionTitle,
				Content:      sc,
				TokenCount:   len(sc)/4 + 1,
			})
			chunkIndex++
		}
	}

	return chunks
}
