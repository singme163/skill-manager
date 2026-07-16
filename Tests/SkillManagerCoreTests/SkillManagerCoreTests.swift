import Testing
import Foundation
@testable import SkillManagerCore

// MARK: - Frontmatter

@Suite struct FrontmatterParserTests {
    @Test func parsesBasicFrontmatter() {
        let md = """
        ---
        name: my-skill
        description: Does something useful.
        ---

        # My Skill
        """
        let meta = FrontmatterParser.parse(markdown: md)
        #expect(meta?.name == "my-skill")
        #expect(meta?.description == "Does something useful.")
    }

    @Test func parsesQuotedAndExtraKeys() {
        let md = """
        ---
        name: "quoted-name"
        version: 1.0
        description: 'single quoted'
        ---
        body
        """
        let keys = FrontmatterParser.parseKeys(markdown: md)
        #expect(keys?["name"] == "quoted-name")
        #expect(keys?["description"] == "single quoted")
        #expect(keys?["version"] == "1.0")
    }

    @Test func parsesFoldedMultilineDescription() {
        let md = """
        ---
        name: folded
        description: >
          Line one continues
          into line two.
        ---
        """
        let meta = FrontmatterParser.parse(markdown: md)
        #expect(meta?.description == "Line one continues into line two.")
    }

    @Test func descriptionWithColonInValue() {
        let md = """
        ---
        name: with-colon
        description: Use when: the user asks for X.
        ---
        """
        let meta = FrontmatterParser.parse(markdown: md)
        #expect(meta?.description == "Use when: the user asks for X.")
    }

    @Test func missingFrontmatterReturnsNil() {
        #expect(FrontmatterParser.parse(markdown: "# Just a heading\n\nText.") == nil)
    }

    @Test func unterminatedFrontmatterReturnsNil() {
        #expect(FrontmatterParser.parse(markdown: "---\nname: broken\n\n# heading") == nil)
    }

    @Test func skillNameValidation() {
        #expect(FrontmatterParser.isValidSkillName("my-skill-2"))
        #expect(FrontmatterParser.isValidSkillName("skill"))
        #expect(!FrontmatterParser.isValidSkillName("My-Skill"))
        #expect(!FrontmatterParser.isValidSkillName("has space"))
        #expect(!FrontmatterParser.isValidSkillName("-leading"))
        #expect(!FrontmatterParser.isValidSkillName("trailing-"))
        #expect(!FrontmatterParser.isValidSkillName(""))
    }

    @Test func templateRoundTrips() {
        let md = FrontmatterParser.templateSkillMarkdown(name: "demo", description: "A demo.")
        let meta = FrontmatterParser.parse(markdown: md)
        #expect(meta?.name == "demo")
        #expect(meta?.description == "A demo.")
    }
}

// MARK: - Tool registry (v1.2)

@Suite struct ToolRegistryTests {
    private func freshDefaults() -> UserDefaults {
        let suite = "test.toolRegistry.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        return defaults
    }

    @Test func saveLoadRoundTrip() {
        let defaults = freshDefaults()
        let custom = ToolRegistry.makeCustomTool(
            name: "Gemini CLI", directoryPath: "~/.gemini/skills", existing: [.claudeCode, .codex]
        )
        ToolRegistry.save([.claudeCode, .codex, custom], defaults: defaults)
        let loaded = ToolRegistry.load(defaults: defaults)

        #expect(loaded.count == 3)
        #expect(loaded.map(\.id).prefix(2) == ["claudeCode", "codex"])
        let reloadedCustom = loaded.first { $0.id == custom.id }
        #expect(reloadedCustom?.name == "Gemini CLI")
        #expect(reloadedCustom?.badge == "Gemini")
        #expect(reloadedCustom?.sortOrder == 2)
        #expect(reloadedCustom?.isBuiltIn == false)
    }

    @Test func firstRunAppliesLegacyPathOverride() {
        let defaults = freshDefaults()
        defaults.set("~/custom/claude-skills", forKey: Tool.claudeCode.pathOverrideDefaultsKey)
        let tools = ToolRegistry.firstRunDefaults(defaults: defaults)

        #expect(tools.contains { $0.id == "claudeCode" && $0.directoryPath == "~/custom/claude-skills" })
        #expect(tools.contains { $0.id == "codex" && $0.directoryPath == "~/.codex/skills" })
    }

    @Test func presetsAreDistinctAndPluginSourceIsReadOnly() {
        #expect(Set(Tool.presets.map(\.id)).count == Tool.presets.count)
        #expect(Tool.claudePlugins.isReadOnly)
        #expect(Tool.claudePlugins.deepScan)
        #expect(!Tool.claudeCode.isReadOnly)
    }
}

// MARK: - Localization

@Suite struct LocalizationTests {
    @Test func localizationTablesLoadAndMatch() throws {
        let zhURL = try #require(Bundle.module.url(
            forResource: "Localizable", withExtension: "strings", subdirectory: nil, localization: "zh-Hans"
        ))
        let enURL = try #require(Bundle.module.url(
            forResource: "Localizable", withExtension: "strings", subdirectory: nil, localization: "en"
        ))
        // NSDictionary parsing also validates .strings syntax.
        let zh = try #require(NSDictionary(contentsOf: zhURL) as? [String: String])
        let en = try #require(NSDictionary(contentsOf: enURL) as? [String: String])
        #expect(!zh.isEmpty)
        #expect(Set(zh.keys) == Set(en.keys))
        #expect(en["下载失败：%@"] == "Download failed: %@")
    }
}

// MARK: - Scanner

private func makeSkill(_ name: String, in dir: URL, markdown: String? = nil) throws {
    let folder = dir.appending(path: name)
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    let md = markdown ?? "---\nname: \(name)\ndescription: desc of \(name)\n---\n\n# \(name)\n"
    try md.write(to: folder.appending(path: "SKILL.md"), atomically: true, encoding: .utf8)
}

@Suite final class SkillScannerTests {
    let tempDir: URL

    init() throws {
        tempDir = try SkillInstaller.makeTempDirectory()
    }

    deinit {
        try? FileManager.default.removeItem(at: tempDir)
    }

    @Test func scanFindsSkillsAndMetadata() throws {
        try makeSkill("alpha", in: tempDir)
        try makeSkill("beta", in: tempDir)
        // A folder without SKILL.md is still listed, but flagged.
        try FileManager.default.createDirectory(
            at: tempDir.appending(path: "no-skill-md"), withIntermediateDirectories: true
        )
        // A stray file at top level is ignored.
        try "x".write(to: tempDir.appending(path: "README.md"), atomically: true, encoding: .utf8)

        let copies = SkillScanner.scan(directory: tempDir, tool: .claudeCode)
        #expect(copies.count == 3)

        let alpha = copies.first { $0.folderName == "alpha" }
        #expect(alpha?.metadataName == "alpha")
        #expect(alpha?.metadataDescription == "desc of alpha")
        #expect(alpha?.hasValidMetadata == true)

        let broken = copies.first { $0.folderName == "no-skill-md" }
        #expect(broken?.hasSkillFile == false)
        #expect(broken?.hasValidMetadata == false)
    }

    @Test func scanMissingDirectoryReturnsEmpty() {
        let missing = tempDir.appending(path: "does-not-exist")
        #expect(SkillScanner.scan(directory: missing, tool: .codex).isEmpty)
    }

    @Test func deepScanFindsNestedSkillsWithRelativeNames() throws {
        // Mimic the plugin cache layout: market/plugin/version/skills/<name>/SKILL.md
        try makeSkill("pdf", in: tempDir.appending(path: "market/plugin-a/1.0/skills"))
        try makeSkill("pdf", in: tempDir.appending(path: "market/plugin-b/2.0/skills"))

        var pluginTool = Tool.claudePlugins
        pluginTool.directoryPath = tempDir.path

        let copies = SkillScanner.scan(tool: pluginTool)
        #expect(copies.count == 2)
        // Relative folder names keep same-named plugin skills distinct.
        #expect(Set(copies.map(\.folderName)) == [
            "market/plugin-a/1.0/skills/pdf",
            "market/plugin-b/2.0/skills/pdf",
        ])
        #expect(copies.allSatisfy { $0.metadataName == "pdf" && $0.hasValidMetadata })

        // And they never merge with a regular skill of the same name.
        let flat = tempDir.appending(path: "flat")
        try makeSkill("pdf", in: flat)
        let merged = Skill.merge(copies + SkillScanner.scan(directory: flat, tool: .claudeCode))
        #expect(merged.count == 3)
    }

    @Test func mergeAcrossTools() throws {
        let claudeDir = tempDir.appending(path: "claude")
        let codexDir = tempDir.appending(path: "codex")
        try makeSkill("shared", in: claudeDir)
        try makeSkill("shared", in: codexDir)
        try makeSkill("only-claude", in: claudeDir)

        let copies = SkillScanner.scan(directory: claudeDir, tool: .claudeCode)
            + SkillScanner.scan(directory: codexDir, tool: .codex)
        let skills = Skill.merge(copies)

        #expect(skills.count == 2)
        let shared = skills.first { $0.folderName == "shared" }
        #expect(shared?.tools.count == 2)
        #expect(shared?.copy(for: .claudeCode) != nil)
        #expect(shared?.copy(for: .codex) != nil)
        let only = skills.first { $0.folderName == "only-claude" }
        #expect(only?.tools == [.claudeCode])
    }
}

// MARK: - Installer

@Suite final class SkillInstallerTests {
    let tempDir: URL

    init() throws {
        tempDir = try SkillInstaller.makeTempDirectory()
    }

    deinit {
        try? FileManager.default.removeItem(at: tempDir)
    }

    private func makeSourceSkill(_ name: String, nestedIn subpath: String? = nil) throws -> URL {
        var base = tempDir.appending(path: "source")
        if let subpath { base = base.appending(path: subpath) }
        let folder = base.appending(path: name)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try "---\nname: \(name)\ndescription: d\n---\n"
            .write(to: folder.appending(path: "SKILL.md"), atomically: true, encoding: .utf8)
        try FileManager.default.createDirectory(
            at: folder.appending(path: "references"), withIntermediateDirectories: true
        )
        try "ref".write(
            to: folder.appending(path: "references/notes.md"), atomically: true, encoding: .utf8
        )
        return folder
    }

    @Test func findSkillRootsDirectAndNested() throws {
        let direct = try makeSourceSkill("direct-skill")
        #expect(SkillInstaller.findSkillRoots(in: direct) == [direct.standardizedFileURL])

        _ = try makeSourceSkill("nested-a", nestedIn: "repo/skills")
        _ = try makeSourceSkill("nested-b", nestedIn: "repo/skills")
        let roots = SkillInstaller.findSkillRoots(in: tempDir.appending(path: "source/repo"))
        #expect(roots.map(\.lastPathComponent).sorted() == ["nested-a", "nested-b"])
    }

    @Test func installCopiesWholeDirectory() throws {
        let source = try makeSourceSkill("to-install")
        let skillsDir = tempDir.appending(path: "skills")
        let candidate = InstallCandidate(name: "to-install", sourceDirectory: source)

        try SkillInstaller.install(candidate: candidate, intoDirectory: skillsDir, tool: .codex, overwrite: false)

        let installed = skillsDir.appending(path: "to-install")
        #expect(FileManager.default.fileExists(atPath: installed.appending(path: "SKILL.md").path))
        #expect(FileManager.default.fileExists(atPath: installed.appending(path: "references/notes.md").path))
    }

    @Test func installConflictWithoutOverwriteThrows() throws {
        let source = try makeSourceSkill("dup")
        let skillsDir = tempDir.appending(path: "skills")
        let candidate = InstallCandidate(name: "dup", sourceDirectory: source)

        try SkillInstaller.install(candidate: candidate, intoDirectory: skillsDir, tool: .codex, overwrite: false)
        #expect(throws: InstallError.alreadyExists(name: "dup", tool: .codex)) {
            try SkillInstaller.install(candidate: candidate, intoDirectory: skillsDir, tool: .codex, overwrite: false)
        }
    }

    @Test func prepareImportFromZip() throws {
        let source = try makeSourceSkill("zipped-skill")
        let zipURL = tempDir.appending(path: "skill.zip")
        let process = Process()
        process.executableURL = URL(filePath: "/usr/bin/ditto")
        process.arguments = ["-c", "-k", source.path, zipURL.path]
        try process.run()
        process.waitUntilExit()
        #expect(process.terminationStatus == 0)

        let candidates = try SkillInstaller.prepareImport(from: zipURL)
        #expect(candidates.count == 1)
        // ditto -c -k on a folder zips its *contents*; the staged temp dir
        // itself becomes the skill root, whatever its generated name.
        #expect(
            FileManager.default.fileExists(
                atPath: candidates[0].sourceDirectory.appending(path: "SKILL.md").path
            )
        )
    }

    @Test func prepareImportRejectsNonSkillFolder() throws {
        let empty = tempDir.appending(path: "not-a-skill")
        try FileManager.default.createDirectory(at: empty, withIntermediateDirectories: true)
        #expect(throws: InstallError.noSkillFound) {
            try SkillInstaller.prepareImport(from: empty)
        }
    }

    @Test func createTemplate() throws {
        let skillsDir = tempDir.appending(path: "skills")
        let created = try SkillInstaller.createTemplate(
            name: "fresh-skill", description: "Testing.", inDirectory: skillsDir, tool: .claudeCode
        )
        let text = try String(contentsOf: created.appending(path: "SKILL.md"), encoding: .utf8)
        let meta = FrontmatterParser.parse(markdown: text)
        #expect(meta?.name == "fresh-skill")
        #expect(meta?.description == "Testing.")

        // Duplicate name is rejected.
        #expect(throws: InstallError.alreadyExists(name: "fresh-skill", tool: .claudeCode)) {
            try SkillInstaller.createTemplate(
                name: "fresh-skill", description: "x", inDirectory: skillsDir, tool: .claudeCode
            )
        }
        // Invalid name is rejected.
        #expect(throws: InstallError.invalidName("Bad Name")) {
            try SkillInstaller.createTemplate(
                name: "Bad Name", description: "x", inDirectory: skillsDir, tool: .claudeCode
            )
        }
    }

    @Test func parseGitHubURLVariants() {
        let repo = SkillInstaller.parseGitHubURL("https://github.com/org/repo")
        #expect(repo == .init(owner: "org", repo: "repo", ref: nil, subpath: nil))

        let git = SkillInstaller.parseGitHubURL("https://github.com/org/repo.git")
        #expect(git?.repo == "repo")

        let tree = SkillInstaller.parseGitHubURL("https://github.com/org/repo/tree/main/skills/foo")
        #expect(tree == .init(owner: "org", repo: "repo", ref: "main", subpath: "skills/foo"))

        let refOnly = SkillInstaller.parseGitHubURL("https://github.com/org/repo/tree/v1.2")
        #expect(refOnly == .init(owner: "org", repo: "repo", ref: "v1.2", subpath: nil))

        #expect(SkillInstaller.parseGitHubURL("https://gitlab.com/org/repo") == nil)
        #expect(SkillInstaller.parseGitHubURL("https://github.com/org") == nil)
        #expect(SkillInstaller.parseGitHubURL("not a url") == nil)
        #expect(SkillInstaller.parseGitHubURL("https://github.com/org/repo/pulls/1") == nil)

        #expect(repo?.zipballURL.absoluteString == "https://api.github.com/repos/org/repo/zipball")
        #expect(tree?.zipballURL.absoluteString == "https://api.github.com/repos/org/repo/zipball/main")
    }
}
