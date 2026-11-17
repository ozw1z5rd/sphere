import Foundation

/// Converts Markdown to readable plain text for clipboard/selection use.
/// This is intentionally line-based and does not require a Markdown renderer:
/// it preserves paragraph breaks, list items, tables and code blocks while
/// removing syntax markers.
public enum MarkdownPlainText {
    public static func plainText(from markdown: String) -> String {
        let normalized = markdown
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")

        var output: [String] = []
        var inFence = false

        for rawLine in normalized.components(separatedBy: "\n") {
            let trimmed = rawLine.trimmingCharacters(in: .whitespaces)

            if trimmed.hasPrefix("```") || trimmed.hasPrefix("~~~") {
                inFence.toggle()
                continue
            }
            if inFence {
                output.append(rawLine)
                continue
            }

            var line = rawLine
            line = line.replacingOccurrences(
                of: "^\\s{0,3}#{1,6}\\s+",
                with: "",
                options: .regularExpression
            )
            line = line.replacingOccurrences(
                of: "^\\s{0,3}>\\s?",
                with: "",
                options: .regularExpression
            )

            if trimmed.range(
                of: "^(\\*\\s*){3,}$|^(-\\s*){3,}$|^(_\\s*){3,}$",
                options: .regularExpression
            ) != nil {
                output.append("")
                continue
            }

            if trimmed.range(
                of: "^\\|?\\s*:?-{3,}:?\\s*(\\|\\s*:?-{3,}:?\\s*)*\\|?$",
                options: .regularExpression
            ) != nil {
                continue
            }

            if trimmed.hasPrefix("|"), trimmed.hasSuffix("|") {
                let cells = trimmed
                    .dropFirst()
                    .dropLast()
                    .split(separator: "|", omittingEmptySubsequences: false)
                    .map { $0.trimmingCharacters(in: .whitespaces) }
                line = cells.joined(separator: " | ")
            }

            line = line.replacingOccurrences(
                of: "^\\s*[-*+]\\s+",
                with: "• ",
                options: .regularExpression
            )
            line = line.replacingOccurrences(
                of: "^(•\\s*)\\[[ xX]\\]\\s*",
                with: "$1",
                options: .regularExpression
            )
            line = inline(line)
            output.append(line)
        }

        let text = output
            .joined(separator: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return text.isEmpty ? markdown.trimmingCharacters(in: .whitespacesAndNewlines) : text
    }

    private static func inline(_ input: String) -> String {
        var text = input
        text = text.replacingOccurrences(
            of: "!\\[([^\\]]*)\\]\\([^)]*\\)",
            with: "$1",
            options: .regularExpression
        )
        text = text.replacingOccurrences(
            of: "\\[([^\\]]+)\\]\\([^)]*\\)",
            with: "$1",
            options: .regularExpression
        )
        text = text.replacingOccurrences(
            of: "`([^`]+)`",
            with: "$1",
            options: .regularExpression
        )
        text = text.replacingOccurrences(
            of: "(\\*\\*|__)(.*?)\\1",
            with: "$2",
            options: .regularExpression
        )
        text = text.replacingOccurrences(
            of: "~~(.*?)~~",
            with: "$1",
            options: .regularExpression
        )
        text = text.replacingOccurrences(
            of: "(\\*|_)(.*?)\\1",
            with: "$2",
            options: .regularExpression
        )
        text = text.replacingOccurrences(
            of: "<[^>]+>",
            with: "",
            options: .regularExpression
        )
        text = text.replacingOccurrences(
            of: "\\\\([\\\\`*{}\\[\\]()#+\\-.!_>])",
            with: "$1",
            options: .regularExpression
        )
        return text
    }
}
