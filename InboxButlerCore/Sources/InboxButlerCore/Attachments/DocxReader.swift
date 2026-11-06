import Foundation

/// Plain text from a .docx (Word) file: paragraphs and tabs, no formatting.
/// Old binary .doc files are not supported.
enum DocxReader {
    static func text(from data: Data) throws -> String {
        let xml = try ZipReader.readEntry(named: "word/document.xml", from: data)
        let parser = XMLParser(data: xml)
        let collector = Collector()
        parser.delegate = collector
        guard parser.parse() else { throw AttachmentTextExtractor.ExtractionError.unreadable }
        return collector.text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private final class Collector: NSObject, XMLParserDelegate {
        var text = ""
        private var inText = false

        func parser(_ parser: XMLParser, didStartElement name: String, namespaceURI: String?,
                    qualifiedName: String?, attributes: [String: String] = [:]) {
            switch name {
            case "w:t": inText = true
            case "w:tab": text += "\t"
            case "w:br": text += "\n"
            default: break
            }
        }
        func parser(_ parser: XMLParser, foundCharacters string: String) {
            if inText { text += string }
        }
        func parser(_ parser: XMLParser, didEndElement name: String, namespaceURI: String?, qualifiedName: String?) {
            if name == "w:t" { inText = false }
            if name == "w:p" { text += "\n" }
        }
    }
}
