import Foundation

@main struct FaceVaultBrokerPolicyTests {
    static func main() throws {
        var checks = 0
        func check(_ value: @autoclosure () -> Bool, _ message: String) {
            precondition(value(), message); checks += 1
        }
        let peer = FaceVaultBrokerPeerIdentity(processID: 123, userID: 501, groupID: 20,
            auditSessionID: 101, startSeconds: 1_700_000_000, startMicroseconds: 42)
        func session(uid: UInt32 = 501, euid: UInt32 = 501, gid: UInt32 = 20, asid: UInt32 = 101,
                     console: UInt32? = 501, onConsole: Bool? = true, login: Bool? = true,
                     unlocked: Bool? = true, graphical: Bool = true, remote: Bool = false, root: Bool = false) -> FaceVaultBrokerLocalSession {
            .init(userID: uid, effectiveUserID: euid, groupID: gid, auditSessionID: asid,
                  consoleUserID: console, onConsole: onConsole, loginComplete: login, unlocked: unlocked,
                  graphical: graphical, remote: remote, root: root)
        }
        check(FaceVaultBrokerPolicy.permits(peer, in: session()), "current owned local GUI session")
        check(FaceVaultBrokerPolicy.permits(peer, in: session(unlocked: nil)), "absent lock key is normal; DP ACL independently controls key access")
        check(FaceVaultBrokerPolicy.refusalPoint(peer,in:session(gid:80)) == .peerGroupPolicy, "fixed group diagnostic")
        check(FaceVaultBrokerPolicy.refusalPoint(peer,in:session(asid:102)) == .peerAuditPolicy, "fixed audit diagnostic")
        check(FaceVaultBrokerPolicy.refusalPoint(peer,in:session(console:nil)) == .peerConsolePolicy, "fixed console diagnostic")
        try FaceVaultBrokerPeerVerifier.validateSessionConfiguration(["ServiceType": "Application", "JoinExistingSession": true])
        checks += 1
        for value: Any? in [nil, [:], ["ServiceType": "Application"],
                           ["ServiceType": "User", "JoinExistingSession": true],
                           ["ServiceType": "Application", "JoinExistingSession": false],
                           ["ServiceType": "Application", "JoinExistingSession": 1],
                           ["ServiceType": "Application", "JoinExistingSession": "true"]] {
            do {
                try FaceVaultBrokerPeerVerifier.validateSessionConfiguration(value)
                preconditionFailure("missing, isolated or malformed caller-session configuration must fail")
            } catch let failure as FaceVaultBrokerFailure {
                check(failure.code == .configurationInvalid && failure.stage == .configuration &&
                      failure.point == .ownSessionConfiguration, "fixed caller-session configuration refusal")
            }
        }
        let absent = try FaceVaultBrokerPeerVerifier.lockState(in: [:])
        let locked = try FaceVaultBrokerPeerVerifier.lockState(in: ["CGSSessionScreenIsLocked": true])
        let unlocked = try FaceVaultBrokerPeerVerifier.lockState(in: ["CGSSessionScreenIsLocked": false])
        check(absent == nil, "only truly absent lock key is optional")
        check(locked == true, "explicit locked Boolean parsed")
        check(unlocked == false, "explicit unlocked Boolean parsed")
        for value: Any in ["false", NSNumber(value: 0), NSNull()] {
            do {
                _ = try FaceVaultBrokerPeerVerifier.lockState(in: ["CGSSessionScreenIsLocked": value])
                preconditionFailure("present malformed lock metadata must fail")
            } catch { checks += 1 }
        }
        for value in [session(uid: 0,euid: 0),session(euid: 502),session(gid: 80),session(asid: 0),session(asid: 102),
                      session(console: 502),session(console: nil),session(onConsole: false),session(onConsole: nil),
                      session(login: false),session(login: nil),session(unlocked: false),session(graphical: false),
                      session(remote: true),session(root: true)] {
            check(!FaceVaultBrokerPolicy.permits(peer, in: value), "unknown/foreign/locked/remote session denied")
        }
        for candidate in [
            FaceVaultBrokerPeerIdentity(processID: 0,userID: 501,groupID: 20,auditSessionID: 101,startSeconds: 1,startMicroseconds: 0),
            .init(processID: 123,userID: 502,groupID: 20,auditSessionID: 101,startSeconds: 1,startMicroseconds: 0),
            .init(processID: 123,userID: 501,groupID: 20,auditSessionID: 101,startSeconds: 0,startMicroseconds: 0),
            .init(processID: 123,userID: 501,groupID: 20,auditSessionID: 101,startSeconds: 1,startMicroseconds: 1_000_000)] {
            check(!FaceVaultBrokerPolicy.permits(candidate, in: session()), "invalid process lifetime/identity denied")
        }
        let id = UUID(), vault = UUID()
        func receipt(at time: TimeInterval = 10) -> FaceVaultBrokerCreationReceipt {
            .init(id: id,vaultID: vault,peer: peer,createdAt: time)
        }
        for time in [10.0,10.01,39.999] {
            var value=receipt()
            check(value.consume(id:id,vaultID:vault,peer:peer,now:time), "fresh exact receipt permits one rollback")
            check(!value.consume(id:id,vaultID:vault,peer:peer,now:time+0.0001), "receipt cannot be replayed")
        }
        for time in [9.999,40,.nan,.infinity,-.infinity] {
            var value=receipt()
            check(!value.consume(id:id,vaultID:vault,peer:peer,now:time), "expired/reversed/invalid receipt time denied")
        }
        for creation in [Double.nan,.infinity,-1] {
            var value=receipt(at: creation)
            check(!value.consume(id:id,vaultID:vault,peer:peer,now:11), "invalid creation time denied")
        }
        var wrong = receipt()
        check(!wrong.consume(id:UUID(),vaultID:vault,peer:peer,now:11), "wrong receipt denied")
        check(!wrong.consume(id:id,vaultID:UUID(),peer:peer,now:11), "wrong vault cannot be deleted")
        let recycled = FaceVaultBrokerPeerIdentity(processID: peer.processID,userID: peer.userID,groupID: peer.groupID,
            auditSessionID: peer.auditSessionID,startSeconds: peer.startSeconds+1,startMicroseconds: peer.startMicroseconds)
        check(!wrong.consume(id:id,vaultID:vault,peer:recycled,now:11), "recycled PID cannot adopt receipt")
        check(!wrong.consumed, "invalid request never authorizes a rollback")
        check(FaceVaultBrokerPolicy.validReason("Protect Notchscape's local Face Vault"), "bounded human-readable purpose")
        for reason in [""," \n","test\nquery",String(repeating:"a",count:201),"bad\u{0}reason"] {
            check(!FaceVaultBrokerPolicy.validReason(reason), "empty/control/unbounded purpose denied")
        }
        let expiration="2026-11-06T01:45:35Z", exact=ISO8601DateFormatter().date(from:expiration)!
        check(FaceVaultBrokerPolicy.validExpiration(expiration,at:exact.addingTimeInterval(-1)), "valid signed expiry")
        check(!FaceVaultBrokerPolicy.validExpiration(expiration,at:exact), "exact expiry denied")
        check(!FaceVaultBrokerPolicy.validExpiration("$(UNEXPANDED)",at:exact), "missing wrapper stamp fails closed")
        let failure=FaceVaultBrokerFailure(code:.storageFailure,stage:.keyRead,status:-34018).wireError
        check(failure.domain==FaceVaultBrokerIdentity.errorDomain && failure.code==FaceVaultBrokerErrorCode.storageFailure.rawValue,
              "bounded semantic error")
        check(Set(failure.userInfo.keys)==[FaceVaultBrokerIdentity.failureStageKey,FaceVaultBrokerIdentity.osStatusKey], "no arbitrary error descriptions/queries/paths")
        check((failure.userInfo[FaceVaultBrokerIdentity.osStatusKey] as? NSNumber)?.int32Value == -34018, "numeric entitlement diagnostic preserved")
        let diagnostic = FaceVaultBrokerFailure(code:.untrustedPeer,stage:.peerValidation,
            point:.peerProcessRead,diagnosticStatus:1).wireError
        check(Set(diagnostic.userInfo.keys)==[FaceVaultBrokerIdentity.failureStageKey], "diagnostic labels/POSIX failures never become arbitrary wire metadata")
        print("PASS \(checks) broker peer/receipt/configuration checks; no RPC/authentication/Keychain/camera")
    }
}
