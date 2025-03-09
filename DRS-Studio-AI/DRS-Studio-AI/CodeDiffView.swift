import SwiftUI

struct CodeDiff {
    let original: String
    let modified: String
    let changes: [(original: Range<String.Index>, modified: Range<String.Index>)]
    
    init(original: String, modified: String) {
        self.original = original
        self.modified = modified
        self.changes = Self.findChanges(original: original, modified: modified)
    }
    
    private static func findChanges(original: String, modified: String) -> [(original: Range<String.Index>, modified: Range<String.Index>)] {
        // Simple diff implementation - can be enhanced with more sophisticated diff algorithm
        let originalLines = original.components(separatedBy: .newlines)
        let modifiedLines = modified.components(separatedBy: .newlines)
        var changes: [(original: Range<String.Index>, modified: Range<String.Index>)] = []
        
        var originalIndex = original.startIndex
        var modifiedIndex = modified.startIndex
        
        for (origLine, modLine) in zip(originalLines, modifiedLines) {
            if origLine != modLine {
                let originalRange = originalIndex..<original.index(originalIndex, offsetBy: origLine.count)
                let modifiedRange = modifiedIndex..<modified.index(modifiedIndex, offsetBy: modLine.count)
                changes.append((originalRange, modifiedRange))
            }
            originalIndex = original.index(originalIndex, offsetBy: origLine.count + 1)
            modifiedIndex = modified.index(modifiedIndex, offsetBy: modLine.count + 1)
        }
        
        return changes
    }
}

struct CodeDiffView: View {
    let original: String
    let modified: String
    @State private var diff: CodeDiff
    
    init(original: String, modified: String) {
        self.original = original
        self.modified = modified
        self._diff = State(initialValue: CodeDiff(original: original, modified: modified))
    }
    
    var body: some View {
        HSplitView {
            VStack {
                Text("Original Code")
                    .font(.headline)
                ScrollView {
                    Text(AttributedString(highlighting: original, ranges: diff.changes.map { $0.original }))
                        .font(.system(size: 14, design: .monospaced))
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .padding()
            
            VStack {
                Text("Modified Code")
                    .font(.headline)
                ScrollView {
                    Text(AttributedString(highlighting: modified, ranges: diff.changes.map { $0.modified }))
                        .font(.system(size: 14, design: .monospaced))
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .padding()
        }
    }
}

extension AttributedString {
    init(highlighting text: String, ranges: [Range<String.Index>]) {
        var attributed = AttributedString(text)
        for range in ranges {
            if let attrRange = Range(range, in: attributed) {
                attributed[attrRange].backgroundColor = .red.opacity(0.2)
                attributed[attrRange].foregroundColor = .red
            }
        }
        self = attributed
    }
} 