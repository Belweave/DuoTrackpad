import Foundation
import CryptoKit
import Security

/// Private identity material never leaves Keychain. Trust is granted only after a code-authenticated session.
struct PairingIdentity {
    let key: Curve25519.KeyAgreement.PrivateKey
    var publicKey: Data { key.publicKey.rawRepresentation }
    init(raw: Data? = nil) throws {
        key = try raw.map { try Curve25519.KeyAgreement.PrivateKey(rawRepresentation: $0) } ?? Curve25519.KeyAgreement.PrivateKey()
    }
}

struct PairedPeer: Codable, Equatable {
    var publicKey: Data
    var name: String
    var serviceID: String
    var address: String?
}

final class PairingStore {
    private let service: String
    init(service: String = "app.duotrackpad.pairing") { self.service = service }
    private func query(_ account: String) -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service, kSecAttrAccount as String: account]
    }
    private func read(_ account: String) throws -> Data? {
        var query = query(account)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = result as? Data else { throw StoreError.keychain(status) }
        return data
    }
    private func write(_ data: Data, account: String) throws {
        let query = query(account)
        let update = [kSecValueData as String: data]
        let status = SecItemUpdate(query as CFDictionary, update as CFDictionary)
        if status == errSecItemNotFound {
            var item = query
            item[kSecValueData as String] = data
            item[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
            let added = SecItemAdd(item as CFDictionary, nil)
            guard added == errSecSuccess else { throw StoreError.keychain(added) }
        } else if status != errSecSuccess { throw StoreError.keychain(status) }
    }
    func identity() throws -> PairingIdentity {
        if let raw = try read("identity") { return try PairingIdentity(raw: raw) }
        let identity = try PairingIdentity()
        try write(identity.key.rawRepresentation, account: "identity")
        return identity
    }
    func peers() throws -> [PairedPeer] {
        guard let data = try read("peers") else { return [] }
        return try JSONDecoder().decode([PairedPeer].self, from: data)
    }
    func save(_ peer: PairedPeer) throws {
        var peers = try peers()
        peers.removeAll { $0.publicKey == peer.publicKey || $0.serviceID == peer.serviceID }
        peers.append(peer)
        try write(JSONEncoder().encode(peers), account: "peers")
    }
    func forgetAll() throws { try write(JSONEncoder().encode([PairedPeer]()), account: "peers") }
    enum StoreError: Error { case keychain(OSStatus) }
}

struct PairingHello: Codable {
    let version: Int
    let publicKey: Data
    let identity: Data
    let name: String
    let resume: Bool

    init(ephemeral: Data, identity: Data, name: String, resume: Bool) {
        version = 2; publicKey = ephemeral; self.identity = identity; self.name = name; self.resume = resume
    }
}

enum PairingHandshake {
    static func key(privateKey: Curve25519.KeyAgreement.PrivateKey, identity: PairingIdentity,
                    local: PairingHello, remote: PairingHello, code: String, isHost: Bool) throws -> SymmetricKey {
        guard remote.version == 2, remote.publicKey.count == 32, remote.identity.count == 32,
              remote.name.utf8.count <= 128, local.resume == remote.resume else { throw Wire.Failure.invalidPacket }
        let ephemeral = try privateKey.sharedSecretFromKeyAgreement(with: .init(rawRepresentation: remote.publicKey))
        var material = ephemeral.withUnsafeBytes { Data($0) }
        if local.resume {
            let stable = try identity.key.sharedSecretFromKeyAgreement(with: .init(rawRepresentation: remote.identity))
            material.append(stable.withUnsafeBytes { Data($0) })
        }
        // Bind both claimed identities and ephemeral keys into the authenticated transcript.
        let client = isHost ? remote : local, host = isHost ? local : remote
        var transcript = Data("DuoTrackpad/2".utf8)
        transcript.append(client.publicKey); transcript.append(host.publicKey)
        transcript.append(client.identity); transcript.append(host.identity)
        transcript.append(local.resume ? 1 : 0)
        return HKDF<SHA256>.deriveKey(inputKeyMaterial: SymmetricKey(data: material),
            salt: local.resume ? Data() : Data(code.utf8), info: transcript, outputByteCount: 32)
    }
}
