import CodexBarCore
import Commander
import Foundation
import Testing
@testable import CodexBarCLI

struct CLIUsageExcludeProviderTests {
    private func parse(_ arguments: [String]) throws -> ParsedValues {
        let program = Program(descriptors: CodexBarCLI.commandDescriptors())
        return try program.resolve(arguments: ["usage"] + arguments).parsedValues
    }

    @Test
    func `repeated exclude options are collected`() throws {
        let values = try self.parse(["--exclude-provider", "codex", "--exclude-provider", "claude"])
        #expect(values.options["excludeProvider"] == ["codex", "claude"])
    }

    @Test
    func `the resolved set loses exactly the excluded providers and keeps their order`() throws {
        let selection = ProviderSelection.custom([.gemini, .codex, .cursor, .claude])
        let values = try self.parse(["--exclude-provider", "codex", "--exclude-provider", "claude"])
        let resolved = try CodexBarCLI.resolveUsageProviders(selection: selection, values: values)
        #expect(resolved == [.gemini, .cursor])

        let all = try CodexBarCLI.resolveUsageProviders(
            selection: .all,
            values: self.parse(["--exclude-provider", "codex"]))
        #expect(all == ProviderSelection.all.asList.filter { $0 != .codex })
    }

    @Test
    func `without the option the resolved set is unchanged`() throws {
        let values = try self.parse(["--provider", "all"])
        #expect(values.options["excludeProvider"] == nil)
        for selection in [ProviderSelection.all, .both, .single(.codex), .custom([.claude, .codex]), .custom([])] {
            #expect(try CodexBarCLI.resolveUsageProviders(selection: selection, values: values) == selection.asList)
        }
    }

    @Test
    func `excluding a provider outside the set is a no-op`() throws {
        let values = try self.parse(["--exclude-provider", "gemini"])
        #expect(try CodexBarCLI.resolveUsageProviders(selection: .single(.codex), values: values) == [.codex])
    }

    @Test
    func `an unknown provider id is a usage error`() throws {
        let values = try self.parse(["--exclude-provider", "not-a-provider"])
        #expect(throws: CLIArgumentError.self) {
            try CodexBarCLI.resolveUsageProviders(selection: .all, values: values)
        }
        let both = try self.parse(["--exclude-provider", "both"])
        #expect(throws: CLIArgumentError.self) {
            try CodexBarCLI.resolveUsageProviders(selection: .all, values: both)
        }
    }

    @Test
    func `excluding every provider prints an empty JSON array and nothing otherwise`() throws {
        let values = try self.parse(["--exclude-provider", "codex"])
        let resolved = try CodexBarCLI.resolveUsageProviders(selection: .single(.codex), values: values)
        #expect(resolved.isEmpty)
        let json = CLIOutputPreferences(format: .json, jsonOnly: false, pretty: false)
        let jsonOnly = CLIOutputPreferences(format: .text, jsonOnly: true, pretty: false)
        let text = CLIOutputPreferences(format: .text, jsonOnly: false, pretty: false)
        let toon = CLIOutputPreferences(format: .json, jsonOnly: false, pretty: false, toonRequested: true)
        #expect(CodexBarCLI.emptyUsageOutput(output: json) == "[]")
        #expect(CodexBarCLI.emptyUsageOutput(output: jsonOnly) == "[]")
        #expect(CodexBarCLI.emptyUsageOutput(output: text) == nil)
        #expect(CodexBarCLI.emptyUsageOutput(output: toon) == nil)
    }

    @Test
    func `account selection is checked on the set after exclusion`() throws {
        let values = try self.parse(["--exclude-provider", "claude", "--account", "work"])
        let resolved = try CodexBarCLI.resolveUsageProviders(selection: .custom([.codex, .claude]), values: values)
        #expect(resolved == [.codex])
        let selection = try CodexBarCLI.decodeTokenAccountSelection(from: values)
        #expect(selection.providerSelectionError(resolved) == nil)
        #expect(selection.providerSelectionError([.codex, .claude]) != nil)
    }
}
