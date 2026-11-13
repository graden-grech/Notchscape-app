import Foundation
import Cocoa
@main struct Tests {
 static func main() throws {
    let key=Data((0..<32).map{UInt8($0)}), payload=Data("{\"type\":\"probe\"}".utf8)
    var a=SBCipher(key:key,outgoing:1,incoming:2), b=SBCipher(key:key,outgoing:2,incoming:1)
    let frame=try a.seal(payload)
    let hex=frame.map{String(format:"%02x",$0)}.joined()
    let expected=try String(contentsOfFile:CommandLine.arguments[1],encoding:.utf8)
    precondition(hex==expected,"Cross-language frame mismatch")
    let opened=try b.open(Data(frame.dropFirst(4)));precondition(opened==payload)
    do { _=try b.open(Data(frame.dropFirst(4)));fatalError("Replay accepted") } catch SBWireError.replay {}
    var corrupt=Data(frame.dropFirst(4));corrupt[corrupt.count-1]^=1
    do { var c=SBCipher(key:key,outgoing:2,incoming:1);_=try c.open(corrupt);fatalError("Tamper accepted") } catch {}
    let r=CGRect(x:-100,y:-200,width:1600,height:900)
    for side in SBSide.allCases {
        for n in [0.0,0.25,0.5,0.75,1.0] {
            let p=SBpointOnEdge(n,r,side)
            precondition(r.contains(p));precondition(abs(SBfraction(p,r,side)-n)<0.002)
        }
    }
    precondition(SBedgeHit(CGPoint(x:r.maxX,y:0),r,.right,1,0))
    precondition(!SBedgeHit(CGPoint(x:r.maxX,y:0),r,.right,-1,0))
    let left=CGRect(x:-1920,y:0,width:1920,height:1080),right=CGRect(x:0,y:0,width:1920,height:1080)
    precondition(!SBexposedEdge(CGPoint(x:-1,y:500),left,.right,[right]),"Local monitor seam became a cross-computer edge")
    precondition(SBexposedEdge(CGPoint(x:-1920,y:500),left,.left,[right]),"Outer selected edge was rejected")
    precondition(SBexposedEdge(CGPoint(x:-1980,y:500),left,.left,[right]),"Mouse delta crossing past the edge was rejected")
    precondition(!SBexposedEdge(CGPoint(x:0,y:500),left,.left,[right]),"Wrong monitor edge accepted")
    precondition(!SBexposedEdge(CGPoint(x:-1920,y:1500),left,.left,[right]),"Point beyond selected monitor accepted")
    precondition(SBpointOnEdge(0.5,left,.left).x == -1919,"Cursor return has an excessive inset")
    let link=SBLink();var wrongRejected=false,done=false,failure:String?
    link.onReady={failure="Wrong pairing key accepted"}
    link.onClose={_ in wrongRejected=true}
    do { _ = try SBrandomBytes(32, fill: { _, _ in errSecNotAvailable }); fatalError("RNG failure accepted") } catch {}
    let normalizedMatches = try SBpairingKey("abcde-fghjk") == SBpairingKey("ABCDE FGHJK")
    precondition(normalizedMatches,"Pairing normalization mismatch")
    let derivationVector = try SBpairingKey("01234-56789").map { String(format:"%02x",$0) }.joined()
    precondition(derivationVector == "6b32b80393dba3e98f03c126a9b144611abb98058e7570c206029881b4bead66","Pairing derivation mismatch")
    let aliasesMatch = try SBpairingKey("OIL23-45678") == SBpairingKey("01123-45678")
    precondition(aliasesMatch,"Typing aliases mismatch")
    for invalid in ["", "123456", "ABCDE-FGHIU", "ABCDE-FGHJKX"] {
        do { _ = try SBpairingKey(invalid); fatalError("Invalid pairing code accepted") } catch {}
    }
    link.connect(host:"127.0.0.1",code:"99999-99999")
    let timeout=Date().addingTimeInterval(12)
    while !wrongRejected && Date()<timeout { RunLoop.main.run(until:Date().addingTimeInterval(0.02)) }
    precondition(wrongRejected && failure==nil,"Wrong pairing was not rejected")
    link.onReady={link.send(["type":"probe","key":65,"down":true])}
    link.onMessage={msg in if msg["type"] as? String=="ack" && msg["side"] as? String=="above" {done=true;link.disconnect()} }
    link.onClose={why in if !done {failure=why} }
    link.connect(host:"127.0.0.1",code:"ABCDE-FGHJK")
    while !done && failure==nil && Date()<timeout {RunLoop.main.run(until:Date().addingTimeInterval(0.02))}
    precondition(done && failure==nil,"Live protocol failed: \(failure ?? "timeout")")
    RunLoop.main.run(until:Date().addingTimeInterval(0.1))
    print("PASS: Swift cipher compatibility, tamper, replay, four-side edge geometry, wrong pairing and live .NET exchange")
 }
}
