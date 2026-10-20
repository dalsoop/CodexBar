import Foundation

/// Opens the hub's existing account UI. Only the address is projected; credentials are never forwarded.
public enum OpenCodexHubManagement {
    public static func accountsURL(
        executablePath: String?,
        provider: OpenCodexHubProvider,
        transport: any OpenCodexAccessTransport = OpenCodexAccessProcessTransport()) async throws -> URL
    {
        guard let binary = OpenCodexHubReader.resolvedExecutablePath(executablePath) else {
            throw OpenCodexHubReaderError.noHubSource("no ocx executable")
        }
        let data: Data
        do {
            data = try await transport.run(.init(
                binary: binary,
                arguments: OpenCodexRuntimeRoleProbe.statusArguments,
                mutation: false,
                timeout: OpenCodexRuntimeRoleProbe.timeout,
                maxOutputBytes: OpenCodexHubReader.maxOutputBytes))
        } catch {
            throw OpenCodexAccessError.communicationFailed
        }
        // Deliberately do not include command output in errors: status contains unrelated private fields.
        guard let url = self.accountsURL(status: data, provider: provider) else {
            throw OpenCodexHubReaderError.noHubSource("no connected, secure management address")
        }
        return url
    }

    public static func accountsURL(status: Data, provider: OpenCodexHubProvider) -> URL? {
        guard status.count <= OpenCodexHubReader.maxOutputBytes,
              let object = try? JSONSerialization.jsonObject(with: status) as? [String: Any],
              OpenCodexAccessParser.number(object["schemaVersion"]) == 1,
              OpenCodexAccessParser.bool((object["proxy"] as? [String: Any])?["running"]) == true
        else { return nil }
        let address: String?
        switch OpenCodexRuntimeRoleProbe.parseRole(status) {
        case .client:
            let connection = object["connection"] as? [String: Any]
            guard connection?["state"] as? String == "connected" else { return nil }
            address = connection?["managementUrl"] as? String
        case .hub:
            address = (object["hub"] as? [String: Any])?["managementPublicOrigin"] as? String
        case .standalone:
            address = (object["dashboard"] as? [String: Any])?["url"] as? String
        case .unknown:
            return nil
        }
        guard let address, let destination = try? OpenCodexDashboardDestination(address),
              var url = URLComponents(url: destination.url, resolvingAgainstBaseURL: false),
              let host = url.host?.lowercased(), !host.isEmpty,
              url.user == nil, url.password == nil, url.query == nil, url.fragment == nil,
              url.path.isEmpty || url.path == "/"
        else { return nil }
        let loopback = ["localhost", "127.0.0.1", "[::1]", "::1"].contains(host)
        // A standalone install may open only its own loopback UI, never a remote fallback.
        guard OpenCodexRuntimeRoleProbe.parseRole(status) != .standalone || loopback else { return nil }
        url.path = "/"
        url.fragment = provider == .openai ? "codex-set" : "providers?provider=\(provider.rawValue)&tab=accounts"
        return url.url
    }
}
