import Foundation

nonisolated enum ProviderEndpointPolicy {
    static func baseURL(for settings: ProviderSettings) throws -> URL {
        switch settings.provider {
        case .openAI, .openRouter:
            guard let url = URL(string: settings.provider.defaultBaseURL) else {
                throw ProviderEndpointError.invalidURL
            }
            return url
        case .custom:
            return try validatedCustomURL(settings.baseURL)
        }
    }

    private static func validatedCustomURL(_ value: String) throws -> URL {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard var components = URLComponents(string: trimmed),
              let scheme = components.scheme?.lowercased(),
              let host = components.host?.lowercased(),
              !host.isEmpty,
              components.user == nil,
              components.password == nil,
              components.query == nil,
              components.fragment == nil else {
            throw ProviderEndpointError.invalidURL
        }

        let localHosts = Set(["localhost", "127.0.0.1", "::1"])
        guard scheme == "https" || (scheme == "http" && localHosts.contains(host)) else {
            throw ProviderEndpointError.insecureURL
        }

        if components.path.hasSuffix("/") && components.path != "/" {
            components.path.removeLast()
        }
        guard let url = components.url else { throw ProviderEndpointError.invalidURL }
        return url
    }
}

nonisolated enum ProviderEndpointError: LocalizedError {
    case invalidURL
    case insecureURL

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            "Enter a valid provider base URL without credentials, query parameters, or fragments."
        case .insecureURL:
            "Custom providers must use HTTPS. HTTP is allowed only for localhost."
        }
    }
}
