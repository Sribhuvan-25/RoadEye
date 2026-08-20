import SwiftUI

/// Renders a report.md string as formatted text instead of raw Markdown
/// syntax. Splits the document into blocks at blank lines; a GFM table block
/// (the only table shape the prompt ever produces -- "Severity Overview")
/// draws as a real grid, everything else renders through SwiftUI's built-in
/// AttributedString(markdown:) so headings, bold, and lists format properly.
struct MarkdownReportView: View {
    let text: String

    private enum Block {
        case table(header: [String], rows: [[String]])
        case text(AttributedString)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            ForEach(Array(blocks.enumerated()), id: \.offset) { _, block in
                switch block {
                case .table(let header, let rows):
                    tableView(header: header, rows: rows)
                case .text(let attr):
                    Text(attr)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var blocks: [Block] {
        let paragraphs = text
            .components(separatedBy: "\n\n")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        return paragraphs.map { para in
            if let table = Self.parseTable(para) {
                return .table(header: table.header, rows: table.rows)
            }
            return .text(Self.attributed(para))
        }
    }

    /// Render one paragraph line by line: a "#" line becomes a heading, a
    /// "- " line becomes a bullet, everything else parses as inline Markdown
    /// (bold, links) via AttributedString. Lines join back with newlines so
    /// mixed blocks (a bold defect title followed by "- " detail lines, as
    /// the report prompt produces) format correctly as one unit.
    private static func attributed(_ para: String) -> AttributedString {
        let lines = para.split(separator: "\n", omittingEmptySubsequences: false)
        var result = AttributedString()

        for (i, line) in lines.enumerated() {
            if line.hasPrefix("#") {
                let level = line.prefix(while: { $0 == "#" }).count
                let title = line.drop(while: { $0 == "#" || $0 == " " })
                var attr = (try? AttributedString(markdown: String(title))) ?? AttributedString(title)
                let pointSize: CGFloat = level <= 1 ? 22 : (level == 2 ? 18 : 16)
                attr.font = .system(size: pointSize, weight: .bold)
                result += attr
            } else if line.hasPrefix("- ") {
                let content = line.dropFirst(2)
                let rest = (try? AttributedString(markdown: String(content))) ?? AttributedString(content)
                result += AttributedString("•  ")
                result += rest
            } else {
                let opts = AttributedString.MarkdownParsingOptions(
                    interpretedSyntax: .inlineOnlyPreservingWhitespace)
                let rest = (try? AttributedString(markdown: String(line), options: opts))
                    ?? AttributedString(line)
                result += rest
            }
            if i < lines.count - 1 { result += AttributedString("\n") }
        }
        return result
    }

    /// A GFM pipe table: a header row, a "|---|---|" separator, then data rows.
    private static func parseTable(_ block: String) -> (header: [String], rows: [[String]])? {
        let lines = block.split(separator: "\n").map(String.init)
        guard lines.count >= 2, lines[0].contains("|"),
              lines[1].replacingOccurrences(of: "|", with: "")
                  .trimmingCharacters(in: CharacterSet(charactersIn: "- :")).isEmpty
        else { return nil }

        func cells(_ line: String) -> [String] {
            line.split(separator: "|")
                .map { $0.trimmingCharacters(in: .whitespaces) }
        }
        let header = cells(lines[0])
        let rows = lines.dropFirst(2).map(cells)
        return (header, rows)
    }

    private func tableView(header: [String], rows: [[String]]) -> some View {
        Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 8) {
            GridRow {
                ForEach(header, id: \.self) { h in
                    Text(h).font(.subheadline.bold())
                }
            }
            Divider().gridCellUnsizedAxes(.horizontal)
            ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                GridRow {
                    ForEach(row, id: \.self) { cell in
                        Text(cell).font(.subheadline)
                    }
                }
            }
        }
        .padding(.vertical, 4)
    }
}
