import CryptoKit
import Foundation

struct FeatureManifestEnvelope: Codable {
    let algorithm: String
    let keyId: String
    let payload: String
    let signature: String
}

private struct FeatureManifestPayload: Decodable {
    let version: Int64
    let issuedAt: String
    let expiresAt: String
    let items: [DiscoverItem]
}

enum FeatureManifestError: LocalizedError {
    case malformed
    case unsupportedKey
    case invalidSignature
    case expired
    case rolledBack

    var errorDescription: String? {
        switch self {
        case .malformed: return "功能清单格式无效"
        case .unsupportedKey: return "功能清单签名版本不受支持"
        case .invalidSignature: return "功能清单签名校验失败"
        case .expired: return "功能清单已过期"
        case .rolledBack: return "功能清单版本回退已被拒绝"
        }
    }
}

enum FeatureManifestStore {
    private static let publicKeyBase64 =
        "PWZpZZis1rfzDHnUAxHaoL59LQ2DLsXvywaULL8jq7A="
    private static let expectedKeyId = "fm-v1"
    private static let versionKey = "xingyan.feature.manifest.version.v1"
    private static let cacheKey = "xingyan.feature.manifest.key.v1"
    private static let fileName = "feature-manifest.v1.enc"

    static func verifyAndCache(_ envelopeData: Data) throws -> [DiscoverItem] {
        let decoded = try decodeAndVerify(envelopeData, allowSameVersion: true)
        try save(envelopeData)
        Keychain.setDeviceBound(
            String(decoded.version),
            for: versionKey
        )
        return decoded.items
    }

    static func cachedItems() -> [DiscoverItem]? {
        guard let data = load() else { return nil }
        return try? decodeAndVerify(
            data,
            allowSameVersion: true
        ).items
    }

    private static func decodeAndVerify(
        _ data: Data,
        allowSameVersion: Bool
    ) throws -> FeatureManifestPayload {
        let decoder = JSONDecoder()
        guard let envelope = try? decoder.decode(
            FeatureManifestEnvelope.self,
            from: data
        ) else { throw FeatureManifestError.malformed }
        guard envelope.algorithm == "Ed25519",
              envelope.keyId == expectedKeyId,
              let publicData = Data(base64Encoded: publicKeyBase64),
              let payloadData = dataFromBase64URL(envelope.payload),
              let signature = dataFromBase64URL(envelope.signature),
              let publicKey = try? Curve25519.Signing.PublicKey(
                  rawRepresentation: publicData
              ),
              publicKey.isValidSignature(signature, for: payloadData)
        else { throw FeatureManifestError.invalidSignature }

        guard let manifest = try? decoder.decode(
            FeatureManifestPayload.self,
            from: payloadData
        ) else { throw FeatureManifestError.malformed }
        let now = Date()
        guard let issued = isoDate(manifest.issuedAt),
              issued.timeIntervalSince(now) < 120,
              let expires = isoDate(manifest.expiresAt),
              expires > issued,
              expires.timeIntervalSince(now) > -30 else {
            throw FeatureManifestError.expired
        }
        let previous = Int64(
            Keychain.get(versionKey) ?? ""
        ) ?? 0
        if manifest.version < previous
            || (!allowSameVersion && manifest.version == previous) {
            throw FeatureManifestError.rolledBack
        }
        return manifest
    }

    private static func dataFromBase64URL(_ value: String) -> Data? {
        var text = value.replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        let padding = (4 - text.count % 4) % 4
        if padding > 0 {
            text += String(repeating: "=", count: padding)
        }
        return Data(base64Encoded: text)
    }

    private static func isoDate(_ value: String) -> Date? {
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [
            .withInternetDateTime,
            .withFractionalSeconds
        ]
        if let date = fractional.date(from: value) { return date }
        return ISO8601DateFormatter().date(from: value)
    }

    private static func save(_ data: Data) throws {
        let sealed = try AES.GCM.seal(data, using: encryptionKey())
        guard let combined = sealed.combined else {
            throw FeatureManifestError.malformed
        }
        let url = cacheURL
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try combined.write(to: url, options: .atomic)
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        var mutable = url
        try? mutable.setResourceValues(values)
        try? FileManager.default.setAttributes(
            [.protectionKey: FileProtectionType.complete],
            ofItemAtPath: url.path
        )
    }

    private static func load() -> Data? {
        guard let encrypted = try? Data(contentsOf: cacheURL),
              let box = try? AES.GCM.SealedBox(combined: encrypted) else {
            return nil
        }
        return try? AES.GCM.open(box, using: encryptionKey())
    }

    private static func encryptionKey() throws -> SymmetricKey {
        if let saved = Keychain.get(cacheKey),
           let data = Data(base64Encoded: saved),
           data.count == 32 {
            return SymmetricKey(data: data)
        }
        let key = SymmetricKey(size: .bits256)
        let raw = key.withUnsafeBytes { Data($0) }
        Keychain.setDeviceBound(
            raw.base64EncodedString(),
            for: cacheKey
        )
        return key
    }

    private static var cacheURL: URL {
        let support = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        )[0]
        return support
            .appendingPathComponent("Xingyan/PrivateData", isDirectory: true)
            .appendingPathComponent(fileName)
    }
}
