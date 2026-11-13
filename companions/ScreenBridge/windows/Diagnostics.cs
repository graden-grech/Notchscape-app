using System.Diagnostics;

namespace ScreenBridge;

static class Diagnostics {
    static readonly object Gate = new();
    public static string FilePath => Path.Combine(
        Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),
        "ScreenBridge",
        "diagnostics.log");

    public static void Write(string area, string? detail = null, Exception? exception = null) {
        try {
            var directory = Path.GetDirectoryName(FilePath)!;
            Directory.CreateDirectory(directory);
            var line = $"{DateTimeOffset.Now:O}\tpid={Environment.ProcessId}\ttid={Environment.CurrentManagedThreadId}\t{area}";
            if (!string.IsNullOrWhiteSpace(detail)) line += "\t" + detail.Replace('\r', ' ').Replace('\n', ' ');
            if (exception != null) {
                line += $"\t{exception.GetType().FullName}: {exception.Message.Replace('\r', ' ').Replace('\n', ' ')}";
                if (!string.IsNullOrWhiteSpace(exception.StackTrace)) line += "\t" + exception.StackTrace.Replace('\r', ' ').Replace('\n', ' ');
            }
            lock (Gate) File.AppendAllText(FilePath, line + Environment.NewLine);
        } catch {
            // Diagnostics must never interfere with input recovery or app shutdown.
        }
    }
}
