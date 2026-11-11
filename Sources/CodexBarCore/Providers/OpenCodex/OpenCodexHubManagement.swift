import Foundation
#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#elseif canImport(Musl)
import Musl
#endif

public enum OpenCodexHubManagementError: Error, Equatable, Sendable {
    case managementAddressRequired
}

/// Opens the hub's existing account UI. Only the address is projected; credentials are never forwarded.
public enum OpenCodexHubManagement {
    public static func accountsURL(
        executablePath: String?,
        provider: OpenCodexHubProvider,
        managementOrigin: String? = nil,
        transport: any OpenCodexAccessTransport = OpenCodexAccessProcessTransport()) async throws -> URL
    {
        if let origin = self.trimmedManagementOrigin(managementOrigin) {
            guard let url = self.remoteAccountsURL(origin: origin, provider: provider) else {
                throw OpenCodexHubManagementError.managementAddressRequired
            }
            return url
        }
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
        guard let url = self.accountsURL(status: data, provider: provider, managementOrigin: managementOrigin) else {
            if self.connectedClient(data) {
                throw OpenCodexHubManagementError.managementAddressRequired
            }
            throw OpenCodexHubReaderError.noHubSource("no connected, secure management address")
        }
        return url
    }

    public static func accountsURL(
        status: Data,
        provider: OpenCodexHubProvider,
        managementOrigin: String? = nil) -> URL?
    {
        if let origin = self.trimmedManagementOrigin(managementOrigin) {
            return self.remoteAccountsURL(origin: origin, provider: provider)
        }
        guard status.count <= OpenCodexHubReader.maxOutputBytes,
              let object = try? JSONSerialization.jsonObject(with: status) as? [String: Any],
              OpenCodexAccessParser.number(object["schemaVersion"]) == 1,
              OpenCodexAccessParser.bool((object["proxy"] as? [String: Any])?["running"]) == true
        else { return nil }
        let role = OpenCodexRuntimeRoleProbe.parseRole(status)
        let address: String?
        switch role {
        case .client:
            let connection = object["connection"] as? [String: Any]
            guard connection?["state"] as? String == "connected" else { return nil }
            // Remote Link reports its data tunnel as managementUrl. It serves no browser UI.
            guard connection?["transport"] as? String != "link" else { return nil }
            address = connection?["managementUrl"] as? String
        case .hub:
            address = (object["hub"] as? [String: Any])?["managementPublicOrigin"] as? String
        case .standalone:
            address = (object["dashboard"] as? [String: Any])?["url"] as? String
        case .unknown:
            return nil
        }
        guard let address, let url = self.originComponents(address) else { return nil }
        // Remote management must be an HTTPS origin. Only standalone owns a local browser UI.
        guard role == .standalone ? self.isLoopback(url) : self.isRemoteManagementOrigin(address) else { return nil }
        return self.accountsURL(origin: url, provider: provider)
    }

    public static func isRemoteManagementOrigin(_ address: String) -> Bool {
        guard let origin = self.trimmedManagementOrigin(address),
              let host = URLComponents(string: origin)?.host,
              // Reject scoped IPv6 before URL normalization can discard its interface identifier.
              !(host.contains(":") && host.contains("%")),
              let url = self.originComponents(origin)
        else { return false }
        return url.scheme?.lowercased() == "https" && !self.isRemoteLoopback(url)
    }

    /// Do not unquote or validate here: invalid nonempty overrides must never become absent defaults.
    static func trimmedManagementOrigin(_ address: String?) -> String? {
        guard let origin = address?.trimmingCharacters(in: .whitespacesAndNewlines), !origin.isEmpty else { return nil }
        return origin
    }

    private static func remoteAccountsURL(origin: String, provider: OpenCodexHubProvider) -> URL? {
        guard self.isRemoteManagementOrigin(origin), let url = self.originComponents(origin) else { return nil }
        return self.accountsURL(origin: url, provider: provider)
    }

    private static func accountsURL(origin: URLComponents, provider: OpenCodexHubProvider) -> URL? {
        var url = origin
        url.path = "/"
        url.fragment = provider == .openai ? "codex-set" : "providers?provider=\(provider.rawValue)&tab=accounts"
        return url.url
    }

    private static func isRemoteLoopback(_ url: URLComponents) -> Bool {
        let host = (url.host ?? "").lowercased().trimmingCharacters(in: CharacterSet(charactersIn: "[]."))
        if host == "localhost" { return true }
        var ipv4 = in_addr()
        if inet_aton(host, &ipv4) == 1 {
            return UInt32(bigEndian: ipv4.s_addr) >> 24 == 127
        }
        var ipv6 = in6_addr()
        guard inet_pton(AF_INET6, host, &ipv6) == 1 else { return false }
        return withUnsafeBytes(of: &ipv6) { bytes in
            let loopback = bytes.prefix(15).allSatisfy { $0 == 0 } && bytes[15] == 1
            let mappedIPv4 = bytes.prefix(10).allSatisfy { $0 == 0 }
                && bytes[10] == 0xFF && bytes[11] == 0xFF && bytes[12] == 127
            return loopback || mappedIPv4
        }
    }

    private static func originComponents(_ address: String) -> URLComponents? {
        guard let destination = try? OpenCodexDashboardDestination(address),
              let url = URLComponents(url: destination.url, resolvingAgainstBaseURL: false),
              url.query == nil, url.fragment == nil, url.path.isEmpty || url.path == "/"
        else { return nil }
        return url
    }

    private static func isLoopback(_ url: URLComponents) -> Bool {
        ["localhost", "127.0.0.1", "[::1]", "::1"].contains(url.host?.lowercased() ?? "")
    }

    private static func connectedClient(_ data: Data) -> Bool {
        guard data.count <= OpenCodexHubReader.maxOutputBytes,
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              OpenCodexAccessParser.number(object["schemaVersion"]) == 1,
              OpenCodexAccessParser.bool((object["proxy"] as? [String: Any])?["running"]) == true,
              OpenCodexRuntimeRoleProbe.parseRole(data) == .client
        else { return false }
        return (object["connection"] as? [String: Any])?["state"] as? String == "connected"
    }
}
