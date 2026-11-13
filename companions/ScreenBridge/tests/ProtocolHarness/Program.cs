using ScreenBridge;
using System.Net;
using System.Net.Sockets;
using System.Text;
using System.Security.Cryptography;

byte[] key=Enumerable.Range(0,32).Select(i=>(byte)i).ToArray();
if(Convert.ToHexString(PairingCode.Derive("01234-56789")).ToLowerInvariant()!="6b32b80393dba3e98f03c126a9b144611abb98058e7570c206029881b4bead66")throw new Exception("Pairing KDF vector mismatch");
if(!PairingCode.Derive("abcde-fghjk").SequenceEqual(PairingCode.Derive("ABCDE FGHJK")))throw new Exception("Pairing normalization mismatch");
if(!PairingCode.TryNormalize("OIL23-45678",out var aliases)||aliases!="0112345678")throw new Exception("Pairing aliases mismatch");
foreach(var invalid in new[]{"", "123456", "ABCDE-FGHIU", "ABCDE-FGHJKX"})if(PairingCode.TryNormalize(invalid,out _))throw new Exception("Invalid code accepted");
byte[] payload=Encoding.UTF8.GetBytes("{\"type\":\"probe\"}");
var a=new Cipher(key,1,2);var b=new Cipher(key,2,1);
var frame=a.Seal(payload);
File.WriteAllText(args[0],Convert.ToHexString(frame).ToLowerInvariant());
if(!b.Open(frame[4..]).SequenceEqual(payload))throw new Exception("Decrypt failed");
try {b.Open(frame[4..]);throw new Exception("Replay accepted");}catch(IOException){}
var tampered=frame[4..];tampered[^1]^=1;
try {new Cipher(key,2,1).Open(tampered);throw new Exception("Tampering accepted");}catch(System.Security.Cryptography.CryptographicException){}
var listener=new TcpListener(IPAddress.Loopback,24872);listener.Start();
Console.WriteLine("Protocol harness ready");
// The first connection uses the wrong pairing secret; the second must succeed.
for(int i=0;i<2;i++) {
    var client=await listener.AcceptTcpClientAsync();var session=new Link(client);bool ready=false,probe=false;
    session.Ready+=()=>ready=true;
    session.Message+=m=>{if(m.GetProperty("type").GetString()=="probe") {probe=true;_=session.Send(new{type="ack",side="above"});}};
    var pairingKey=PairingCode.Derive("ABCDE-FGHJK");
    await session.Run(pairingKey);
    if(i==0 && ready)throw new Exception("Wrong pairing key accepted");
    if(i==1 && (!ready||!probe))throw new Exception("Live handshake or encrypted message failed");
}
listener.Stop();Console.WriteLine("PASS: .NET cipher, tamper, replay, wrong pairing and live Swift/.NET exchange");
