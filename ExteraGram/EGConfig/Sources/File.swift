import Foundation
import BuildConfig

public struct EGConfig: Codable {
    public var apiUrl: String = "https://api.swiftgram.app"
    public var webappUrl: String = "https://my.swiftgram.app"
    public var botUsername: String = "ExteraGramBot"
    public var publicKey: String?
}

private func parseEGConfig(_ jsonString: String) -> EGConfig {
    let jsonData = Data(jsonString.utf8)
    let decoder = JSONDecoder()
    decoder.keyDecodingStrategy = .convertFromSnakeCase
    return (try? decoder.decode(EGConfig.self, from: jsonData)) ?? EGConfig()
}

private let baseAppBundleId = Bundle.main.bundleIdentifier!
private let buildConfig = BuildConfig(baseAppBundleId: baseAppBundleId)
public let EG_CONFIG: EGConfig = parseEGConfig(buildConfig.egConfig)
public let EG_API_WEBAPP_URL_PARSED = URL(string: EG_CONFIG.webappUrl)!