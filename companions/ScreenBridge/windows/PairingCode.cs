using System.Security.Cryptography;
using System.Text;

namespace ScreenBridge;

static class PairingCode {
    const string Alphabet = "0123456789ABCDEFGHJKMNPQRSTVWXYZ";
    static readonly byte[] Salt = Encoding.ASCII.GetBytes("ScreenBridge pairing v1");

    public static string Create() {
        Span<char> raw = stackalloc char[10];
        for (var index = 0; index < raw.Length; index++) raw[index] = Alphabet[RandomNumberGenerator.GetInt32(Alphabet.Length)];
        return string.Concat(raw[..5], "-", raw[5..]);
    }

    public static bool TryNormalize(string value, out string normalized) {
        var characters = new List<char>(10);
        foreach (var source in value.ToUpperInvariant()) {
            if (source is '-' or ' ') continue;
            var character = source switch { 'O' => '0', 'I' or 'L' => '1', _ => source };
            if (!Alphabet.Contains(character)) { normalized = string.Empty; return false; }
            characters.Add(character);
        }
        normalized = new string(characters.ToArray());
        return normalized.Length == 10;
    }

    public static byte[] Derive(string value) {
        if (!TryNormalize(value, out var normalized)) throw new FormatException("Pairing code must contain 10 valid characters.");
        return Rfc2898DeriveBytes.Pbkdf2(
            Encoding.UTF8.GetBytes(normalized),
            Salt,
            600_000,
            HashAlgorithmName.SHA256,
            32);
    }
}
