import Foundation

/// Parses the indentation-based layout config format:
///
///     split: columns
///     left:
///       run: claude
///     right:
///       split: rows
///       top:
///         run: bin/launch
///       bottom:
///         visit: https://neeto.com
///
class LayoutParser {
    private struct Line {
        let indent: Int
        let key: String
        let value: String
    }

    private var lines: [Line] = []
    private var index = 0

    func parse(_ text: String) -> LayoutNode? {
        lines = text
            .components(separatedBy: .newlines)
            .compactMap { parseLine($0) }
        index = 0
        return parseNode()
    }

    private func parseLine(_ raw: String) -> Line? {
        let stripped = raw.drop(while: { $0 == " " || $0 == "\t" })
        guard !stripped.isEmpty else { return nil }

        let indent = raw.count - stripped.count
        let parts = stripped.split(separator: ":", maxSplits: 1)
        let key = String(parts[0]).trimmingCharacters(in: .whitespaces)
        let value = parts.count > 1
            ? String(parts[1]).trimmingCharacters(in: .whitespaces)
            : ""
        return Line(indent: indent, key: key, value: value)
    }

    private func parseNode() -> LayoutNode? {
        guard index < lines.count else { return nil }
        let line = lines[index]

        switch line.key {
        case "run":
            index += 1
            return .run(command: line.value)

        case "visit":
            index += 1
            return .visit(url: line.value)

        case "split":
            let direction: SplitDirection = line.value == "columns" ? .columns : .rows
            index += 1
            skipLabel()
            guard let first = parseNode() else { return nil }
            skipLabel()
            guard let second = parseNode() else { return nil }
            return .split(direction: direction, first: first, second: second)

        case "tabs":
            index += 1
            var children: [LayoutNode] = []
            while index < lines.count {
                let next = lines[index]
                if next.key == "run" || next.key == "visit" {
                    if let node = parseNode() {
                        children.append(node)
                    }
                } else {
                    break
                }
            }
            return children.isEmpty ? nil : .tabs(children)

        default:
            // Unknown key (possibly a label we missed) — skip it
            index += 1
            return parseNode()
        }
    }

    /// Skip label lines like "left:", "right:", "top:", "bottom:"
    private func skipLabel() {
        guard index < lines.count else { return }
        let key = lines[index].key
        if ["left", "right", "top", "bottom"].contains(key) {
            index += 1
        }
    }
}
