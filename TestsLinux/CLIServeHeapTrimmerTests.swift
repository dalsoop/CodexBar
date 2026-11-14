#if canImport(Glibc)
import CodexBarCore
import Foundation
import Testing

struct CLIServeHeapTrimmerTests {
    @Test
    func `serve releases transient cost scan memory while remaining healthy`() async throws {
        let binary = URL(fileURLWithPath: CommandLine.arguments[0])
            .deletingLastPathComponent().appendingPathComponent("CodexBarCLI")
        let script = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Scripts/test_linux_serve_memory.py")
        let result = try await SubprocessRunner.run(
            binary: "/usr/bin/python3",
            arguments: [script.path, binary.path],
            environment: ["PATH": "/usr/bin:/bin"],
            // Above the fixture's own bounds: 30 s readiness, three 300 s requests, 75 s idle wait, 20 s shutdown.
            timeout: 1200,
            label: "serve-heap-fixture")
        #expect(result.stdout.contains("heap-relief-ok"))
    }
}
#endif
