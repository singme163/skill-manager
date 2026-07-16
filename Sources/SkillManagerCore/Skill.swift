import Foundation

/// One installed copy of a skill inside a specific tool's skills directory.
public struct SkillCopy: Identifiable, Hashable, Sendable {
    public let tool: Tool
    public let directoryURL: URL
    public let folderName: String
    public let metadataName: String?
    public let metadataDescription: String?
    public let hasSkillFile: Bool
    public let hasValidMetadata: Bool
    public let sizeBytes: Int64
    public let modifiedDate: Date

    public init(
        tool: Tool,
        directoryURL: URL,
        folderName: String,
        metadataName: String?,
        metadataDescription: String?,
        hasSkillFile: Bool,
        hasValidMetadata: Bool,
        sizeBytes: Int64,
        modifiedDate: Date
    ) {
        self.tool = tool
        self.directoryURL = directoryURL
        self.folderName = folderName
        self.metadataName = metadataName
        self.metadataDescription = metadataDescription
        self.hasSkillFile = hasSkillFile
        self.hasValidMetadata = hasValidMetadata
        self.sizeBytes = sizeBytes
        self.modifiedDate = modifiedDate
    }

    public var id: String { "\(tool.id):\(folderName)" }
    public var displayName: String { metadataName ?? folderName }
    public var skillFileURL: URL { directoryURL.appending(path: "SKILL.md") }
}

/// A skill merged across tools by folder name (the "已双端安装" view).
public struct Skill: Identifiable, Hashable, Sendable {
    public let folderName: String
    public let copies: [SkillCopy]

    public init(folderName: String, copies: [SkillCopy]) {
        self.folderName = folderName
        self.copies = copies.sorted { $0.tool.sortOrder < $1.tool.sortOrder }
    }

    public var id: String { folderName }
    public var displayName: String { copies.first?.displayName ?? folderName }
    public var summary: String? { copies.compactMap(\.metadataDescription).first }
    public var tools: [Tool] { copies.map(\.tool) }
    public var latestModified: Date { copies.map(\.modifiedDate).max() ?? .distantPast }
    public var maxSizeBytes: Int64 { copies.map(\.sizeBytes).max() ?? 0 }
    public var metadataMissing: Bool { copies.contains { !$0.hasValidMetadata } }

    public func copy(for tool: Tool) -> SkillCopy? {
        copies.first { $0.tool.id == tool.id }
    }

    /// Copies living in sources the user can modify (not read-only).
    public var writableCopies: [SkillCopy] {
        copies.filter { !$0.tool.isReadOnly }
    }

    /// Merge per-tool copies into unified skills, keyed by folder name.
    public static func merge(_ copies: [SkillCopy]) -> [Skill] {
        let grouped = Dictionary(grouping: copies, by: \.folderName)
        return grouped.map { Skill(folderName: $0.key, copies: $0.value) }
            .sorted { $0.folderName.localizedCaseInsensitiveCompare($1.folderName) == .orderedAscending }
    }
}
