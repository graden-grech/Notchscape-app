using System.Buffers.Binary;
using System.Security.Cryptography;
using System.Text;
using System.Text.Json;
using System.Net.Sockets;

namespace ScreenBridge;
public sealed class Cipher(byte[] key, uint outgoing, uint incoming) {
    ulong sent, received;
    public byte[] Seal(byte[] payload) {
        var body = new byte[payload.Length+28];
        BinaryPrimitives.WriteUInt32BigEndian(body, outgoing);
        BinaryPrimitives.WriteUInt64BigEndian(body.AsSpan(4), ++sent);
        using var aes = new AesGcm(key,16);
        aes.Encrypt(body.AsSpan(0,12),payload,body.AsSpan(12,payload.Length),body.AsSpan(body.Length-16));
        var frame = new byte[body.Length+4];
        BinaryPrimitives.WriteInt32BigEndian(frame,body.Length); body.CopyTo(frame,4); return frame;
    }
    public byte[] Open(byte[] body) {
        if (body.Length<28 || body.Length>65536) throw new IOException("Invalid frame");
        ulong counter = BinaryPrimitives.ReadUInt64BigEndian(body.AsSpan(4));
        if(BinaryPrimitives.ReadUInt32BigEndian(body)!=incoming || counter!=received+1) throw new IOException("Replay rejected");
        var plain = new byte[body.Length-28];
        using var aes = new AesGcm(key,16);
        aes.Decrypt(body.AsSpan(0,12),body.AsSpan(12,plain.Length),body.AsSpan(body.Length-16),plain);
        received = counter; return plain;
    }
}
public sealed class Link : IDisposable {
    TcpClient client;
    NetworkStream stream;
    Cipher? cipher;
    readonly SemaphoreSlim gate = new(1);
    readonly CancellationTokenSource cancel = new();
    DateTime lastReceived = DateTime.UtcNow;
    public event Action<JsonElement>? Message;
    public event Action<string>? Closed;
    public event Action? Ready;
    public event Action? AuthenticationFailed;
    public Link(TcpClient client) { this.client=client; stream=client.GetStream(); client.NoDelay=true; }
    public static byte[] Mac(byte[] key, byte[] bytes) => HMACSHA256.HashData(key,bytes);
    public static byte[] Join(params byte[][] chunks) => chunks.SelectMany(c=>c).ToArray();
    async Task<byte[]> Read(int length) {
        var data=new byte[length]; await stream.ReadExactlyAsync(data,cancel.Token); return data;
    }
    public async Task Run(byte[] secret) {
        try {
            using var handshakeTimeout = new CancellationTokenSource(TimeSpan.FromSeconds(6));
            using var handshakeRegistration = handshakeTimeout.Token.Register(()=>Dispose());
            var server=RandomNumberGenerator.GetBytes(32);
            await stream.WriteAsync(Join(Encoding.ASCII.GetBytes("SB01"),server),cancel.Token);
            var hello=await Read(64);
            var challenge=Join(server,hello[..32]);
            if(!CryptographicOperations.FixedTimeEquals(hello[32..],Mac(secret,Join(challenge,Encoding.ASCII.GetBytes("client"))))) {
                AuthenticationFailed?.Invoke();
                throw new IOException("Pairing failed");
            }
            await stream.WriteAsync(Mac(secret,Join(challenge,Encoding.ASCII.GetBytes("server"))),cancel.Token);
            cipher=new Cipher(Mac(secret,Join(challenge,Encoding.ASCII.GetBytes("session"))),2,1);
            handshakeTimeout.CancelAfter(Timeout.InfiniteTimeSpan);
            lastReceived=DateTime.UtcNow; Ready?.Invoke();
            _=Heartbeat();
            while(!cancel.IsCancellationRequested) {
                int length=BinaryPrimitives.ReadInt32BigEndian(await Read(4));
                if(length<28 || length>65536) throw new IOException("Invalid frame");
                var payload=cipher.Open(await Read(length));
                using var doc=JsonDocument.Parse(payload);
                var msg=doc.RootElement.Clone();
                lastReceived=DateTime.UtcNow;
                var type=msg.GetProperty("type").GetString();
                if(type=="ping") await Send(new {type="pong"});
                else if(type!="pong") Message?.Invoke(msg);
            }
        } catch(Exception e) { Closed?.Invoke(e is OperationCanceledException ? "Disconnected" : "Connection ended: "+e.Message); }
        finally { Dispose(); }
    }
    async Task Heartbeat() {
        try {
            while(!cancel.IsCancellationRequested) {
                await Task.Delay(1000,cancel.Token);
                if((DateTime.UtcNow-lastReceived).TotalSeconds>6) { Dispose(); break; }
                await Send(new {type="ping"});
            }
        } catch { Dispose(); }
    }
    public async Task Send(object msg) {
        if(cipher==null || cancel.IsCancellationRequested) return;
        try {
            await gate.WaitAsync(cancel.Token);
            try { await stream.WriteAsync(cipher.Seal(JsonSerializer.SerializeToUtf8Bytes(msg)),cancel.Token); }
            finally { gate.Release(); }
        } catch { Dispose(); }
    }
    public void Dispose() { if(!cancel.IsCancellationRequested) cancel.Cancel(); client.Close(); }
}
