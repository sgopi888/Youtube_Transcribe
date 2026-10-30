import SwiftUI

/// Minimal block renderer for the summary: headings, bullets, numbered items, code fences, paragraphs.
/// shortcut: no tables or nested lists; upgrade to a markdown package if summaries need them.
struct MarkdownView: View {
    let text: String

    private enum Block {
        case h1(String), h2(String), h3(String), bullet(String), numbered(String, String), code(String), para(String)
    }

    private var blocks: [Block] {
        var out: [Block] = []
        var code: [String]?
        for raw in text.components(separatedBy: "\n") {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line.hasPrefix("```") {
                if let c = code { out.append(.code(c.joined(separator: "\n"))); code = nil } else { code = [] }
            } else if code != nil { code?.append(raw) }
            else if line.isEmpty { continue }
            else if line.hasPrefix("### ") { out.append(.h3(String(line.dropFirst(4)))) }
            else if line.hasPrefix("## ") { out.append(.h2(String(line.dropFirst(3)))) }
            else if line.hasPrefix("# ") { out.append(.h1(String(line.dropFirst(2)))) }
            else if line.hasPrefix("- ") || line.hasPrefix("* ") { out.append(.bullet(String(line.dropFirst(2)))) }
            else if let r = line.range(of: #"^\d+[.)] "#, options: .regularExpression) {
                out.append(.numbered(String(line[r]).trimmingCharacters(in: .whitespaces), String(line[r.upperBound...])))
            } else { out.append(.para(line)) }
        }
        if let c = code { out.append(.code(c.joined(separator: "\n"))) }
        return out
    }

    private func inline(_ s: String) -> Text {
        var attr = (try? AttributedString(markdown: s, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace))) ?? AttributedString(s)
        // Summary text comes from the model (and indirectly the video), so only web links stay clickable.
        for run in attr.runs where run.link != nil {
            if !["http", "https"].contains(run.link?.scheme?.lowercased() ?? "") { attr[run.range].link = nil }
        }
        return Text(attr)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(Array(blocks.enumerated()), id: \.offset) { _, block in
                switch block {
                case .h1(let s): inline(s).font(.title.bold())
                case .h2(let s):
                    inline(s).font(.title3.bold()).foregroundStyle(Theme.accentText).padding(.top, 10)
                case .h3(let s): inline(s).font(.headline).padding(.top, 4)
                case .bullet(let s):
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Circle().fill(Theme.cyan.opacity(0.8)).frame(width: 5, height: 5).offset(y: -2)
                        inline(s).fixedSize(horizontal: false, vertical: true)
                    }
                case .numbered(let n, let s):
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(n).foregroundStyle(Theme.accentText).monospacedDigit()
                        inline(s).fixedSize(horizontal: false, vertical: true)
                    }
                case .code(let s):
                    Text(s).font(.system(.callout, design: .monospaced)).padding(10)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(.black.opacity(0.35), in: RoundedRectangle(cornerRadius: 8))
                        .overlay(RoundedRectangle(cornerRadius: 8).stroke(.white.opacity(0.08)))
                case .para(let s): inline(s).fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .lineSpacing(3)
        .textSelection(.enabled)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
