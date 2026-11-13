// Integrated from the user-owned ScreenBridge project; see companions/ScreenBridge/PROVENANCE.md.
import Foundation
import CryptoKit
import Network
import CommonCrypto

func SBpairingKey(_ code:String) throws -> Data {
    let alphabet = Set("0123456789ABCDEFGHJKMNPQRSTVWXYZ")
    let normalized = code.uppercased().filter { $0 != "-" && $0 != " " }.map {
        $0 == "O" ? Character("0") : ($0 == "I" || $0 == "L" ? Character("1") : $0)
    }
    guard normalized.count == 10, normalized.allSatisfy({ alphabet.contains($0) }) else { throw SBWireError.invalid }
    let password = Array(String(normalized).utf8)
    let salt = Array("ScreenBridge pairing v1".utf8)
    var key = Data(count:32)
    let result = key.withUnsafeMutableBytes { output in
        password.withUnsafeBytes { pass in
            salt.withUnsafeBytes { saltBytes in
                CCKeyDerivationPBKDF(CCPBKDFAlgorithm(kCCPBKDF2), pass.baseAddress!.assumingMemoryBound(to:CChar.self), password.count, saltBytes.baseAddress!.assumingMemoryBound(to:UInt8.self), salt.count, CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA256), 600_000, output.baseAddress!.assumingMemoryBound(to:UInt8.self), 32)
            }
        }
    }
    guard result == kCCSuccess else { throw SBWireError.invalid }
    return key
}

enum SBWireError: Error { case invalid, authentication, replay }
func SBrandomBytes(_ count: Int, fill: (Int, UnsafeMutableRawPointer) -> OSStatus = { SecRandomCopyBytes(kSecRandomDefault, $0, $1) }) throws -> Data {
    guard count > 0, count <= 1024 else { throw SBWireError.invalid }
    var data = Data(count: count)
    let result = data.withUnsafeMutableBytes { fill(count, $0.baseAddress!) }
    guard result == errSecSuccess else { throw SBWireError.authentication }
    return data
}
func SBmac(_ key: Data, _ value: Data) -> Data {
    Data(HMAC<SHA256>.authenticationCode(for: value, using: SymmetricKey(data: key)))
}
func SBequal(_ a: Data, _ b: Data) -> Bool {
    guard a.count == b.count else { return false }
    return zip(a,b).reduce(UInt8(0)) { $0 | ($1.0 ^ $1.1) } == 0
}
func SBinteger(_ n: UInt64, bytes: Int) -> Data {
    Data((0..<bytes).reversed().map { UInt8(truncatingIfNeeded: n >> ($0*8)) })
}
struct SBCipher {
    let key: Data
    let outgoing: UInt32
    let incoming: UInt32
    var sent: UInt64 = 0
    var received: UInt64 = 0
    mutating func seal(_ payload: Data) throws -> Data {
        sent += 1
        let nonce = SBinteger(UInt64(outgoing), bytes: 4) + SBinteger(sent, bytes: 8)
        let box = try AES.GCM.seal(payload, using: SymmetricKey(data:key), nonce: AES.GCM.Nonce(data:nonce))
        let body = nonce + box.ciphertext + box.tag
        return SBinteger(UInt64(body.count), bytes:4) + body
    }
    mutating func open(_ body: Data) throws -> Data {
        guard body.count >= 28 && body.count <= 65536 else { throw SBWireError.invalid }
        let prefix = body.prefix(4).reduce(UInt32(0)) { ($0<<8)|UInt32($1) }
        let counter = body.dropFirst(4).prefix(8).reduce(UInt64(0)) { ($0<<8)|UInt64($1) }
        guard prefix == incoming && counter == received+1 else { throw SBWireError.replay }
        let box = try AES.GCM.SealedBox(nonce: AES.GCM.Nonce(data:body.prefix(12)), ciphertext:body.dropFirst(12).dropLast(16), tag:body.suffix(16))
        let result = try AES.GCM.open(box, using:SymmetricKey(data:key))
        received = counter
        return result
    }
}
// One queue owns all framing, handshake and encryption state.
final class SBLink {
    private let queue = DispatchQueue(label:"ScreenBridge.network")
    private var connection: NWConnection?
    private var buffer = Data()
    private var secret = Data()
    private var challenge = Data()
    private var cipher: SBCipher?
    private var generation: UInt64 = 0
    private var phase = 0
    private var active = false
    private var timer: DispatchSourceTimer?
    private var lastReceived = Date()
    private var pendingWrites = 0
    var onReady: (() -> Void)?
    var onMessage: (([String:Any]) -> Void)?
    var onClose: ((String) -> Void)?
    func connect(host:String, code:String) {
        queue.async { [self] in
            self.close("Disconnected", notify:false)
            guard let key = try? SBpairingKey(code) else { self.report("Type the 10-character pairing code shown on Windows."); return }
            self.secret = key
            self.pendingWrites = 0; self.buffer = Data(); self.phase = 0; self.cipher = nil; self.active = true
            self.lastReceived = Date()
            let parameters = NWParameters.tcp
            let options = parameters.defaultProtocolStack.transportProtocol as? NWProtocolTCP.Options
            options?.noDelay = true
            let conn = NWConnection(host:NWEndpoint.Host(host), port:24872, using:parameters)
            self.connection = conn
            conn.stateUpdateHandler = { [weak self, weak conn] state in
                guard let self, let conn, self.connection === conn else { return }
                switch state {
                case .ready: self.receive(conn)
                case .failed(let e): self.close("Connection failed: \(e.localizedDescription)")
                default: break
                }
            }
            conn.start(queue:self.queue)
            let timer = DispatchSource.makeTimerSource(queue:self.queue)
            timer.schedule(deadline:.now()+1, repeating:1)
            timer.setEventHandler { [weak self] in
                guard let self else { return }
                if Date().timeIntervalSince(self.lastReceived)>6 { self.close("Connection timed out. Control returned to this Mac.") }
                else if self.cipher != nil { self.sendNow(["type":"ping"]) }
            }
            self.timer = timer; timer.resume()
        }
    }
    func disconnect() { queue.async { self.close("Disconnected") } }
    func send(_ message:[String:Any]) { queue.async { self.sendNow(message) } }
    private func deliver(_ action: @escaping () -> Void) {
        let expected = generation
        DispatchQueue.main.async { [weak self] in
            guard let self, self.queue.sync(execute: { self.generation == expected }) else { return }
            action()
        }
    }
    private func report(_ value:String) { deliver { [weak self] in self?.onClose?(value) } }
    private func close(_ why:String, notify:Bool = true) {
        generation &+= 1
        let wasActive = active
        active = false; timer?.cancel(); timer = nil
        connection?.cancel(); connection = nil; cipher = nil
        buffer.removeAll(); secret = Data(); challenge = Data()
        if notify && wasActive { report(why) }
    }
    private func raw(_ data:Data) {
        guard let conn=connection else { return }
        pendingWrites += 1
        guard pendingWrites <= 256 else { close("Connection too slow. Control returned to this Mac."); return }
        conn.send(content:data, completion:.contentProcessed { [weak self, weak conn] error in
            guard let self, let conn, self.connection === conn else { return }
            self.pendingWrites -= 1
            if error != nil { self.close("Network interrupted. Control returned to this Mac.") }
        })
    }
    private func sendNow(_ message:[String:Any]) {
        guard var box = cipher else { return }
        do {
            let payload = try JSONSerialization.data(withJSONObject:message, options:.sortedKeys)
            let frame = try box.seal(payload); cipher = box; raw(frame)
        } catch { close("Could not send input.") }
    }
    private func receive(_ conn:NWConnection) {
        conn.receive(minimumIncompleteLength:1, maximumLength:65540) { [weak self, weak conn] data,_,complete,error in
            guard let self, let conn, self.connection === conn else { return }
            if let data { self.buffer.append(data) }
            do { try self.parse() } catch { self.close("Pairing or authentication failed."); return }
            if complete || error != nil { self.close("Windows disconnected. Control returned to this Mac."); return }
            if self.active { self.receive(conn) }
        }
    }
    private func parse() throws {
        while active {
            if phase == 0 {
                guard buffer.count >= 36 else { return }
                guard buffer.prefix(4) == Data("SB01".utf8) else { throw SBWireError.invalid }
                let server = Data(buffer[4..<36]); buffer = Data(buffer.dropFirst(36))
                let client = try SBrandomBytes(32); challenge = server+client
                raw(client + SBmac(secret,challenge+Data("client".utf8))); phase = 1
            } else if phase == 1 {
                guard buffer.count >= 32 else { return }
                guard SBequal(Data(buffer.prefix(32)), SBmac(secret,challenge+Data("server".utf8))) else { throw SBWireError.authentication }
                buffer = Data(buffer.dropFirst(32))
                cipher = SBCipher(key:SBmac(secret,challenge+Data("session".utf8)), outgoing:1, incoming:2)
                secret = Data(); challenge = Data(); phase = 2; lastReceived = Date()
                deliver { [weak self] in self?.onReady?() }
            } else {
                guard buffer.count >= 4 else { return }
                let length = buffer.prefix(4).reduce(0) { ($0<<8)|Int($1) }
                guard length >= 28 && length <= 65536 else { throw SBWireError.invalid }
                guard buffer.count >= length+4 else { return }
                let body = Data(buffer[4..<length+4]); buffer = Data(buffer.dropFirst(length+4))
                guard var box = cipher else { throw SBWireError.invalid }
                let payload = try box.open(body); cipher = box
                guard let obj = try JSONSerialization.jsonObject(with:payload) as? [String:Any], let type = obj["type"] as? String else { throw SBWireError.invalid }
                lastReceived = Date()
                if type == "ping" { sendNow(["type":"pong"]) }
                else if type != "pong" { deliver { [weak self] in self?.onMessage?(obj) } }
            }
        }
    }
}
