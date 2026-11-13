using System.Collections.Concurrent;
using System.Runtime.InteropServices;
using System.Text.Json;

namespace ScreenBridge;

public enum Side { right, left, above, below }

internal static class DisplayPortal {
    internal static int SelectExtremeIndex(IReadOnlyList<Rectangle> displays, Side edge) {
        if (displays.Count == 0) return -1;
        var indices = Enumerable.Range(0, displays.Count);
        return edge switch {
            Side.left => indices.OrderBy(index => displays[index].Left).ThenBy(index => displays[index].Top).ThenBy(index => index).First(),
            Side.right => indices.OrderByDescending(index => displays[index].Right).ThenBy(index => displays[index].Top).ThenBy(index => index).First(),
            Side.above => indices.OrderBy(index => displays[index].Top).ThenBy(index => displays[index].Left).ThenBy(index => index).First(),
            _ => indices.OrderByDescending(index => displays[index].Bottom).ThenBy(index => displays[index].Left).ThenBy(index => index).First()
        };
    }

    static bool Edge(Point point, Rectangle selected, Side side, int dx, int dy) {
        return side switch {
            Side.right => point.Y >= selected.Top && point.Y < selected.Bottom && point.X >= selected.Right - 2 && dx > 0,
            Side.left => point.Y >= selected.Top && point.Y < selected.Bottom && point.X <= selected.Left + 1 && dx < 0,
            Side.above => point.X >= selected.Left && point.X < selected.Right && point.Y <= selected.Top + 1 && dy < 0,
            _ => point.X >= selected.Left && point.X < selected.Right && point.Y >= selected.Bottom - 2 && dy > 0
        };
    }

    static bool BoundaryBlocked(Point point, Rectangle selected, IReadOnlyList<Rectangle> displays, Side side) {
        var outside = side switch {
            Side.right => new Point(selected.Right, Math.Clamp(point.Y, selected.Top, selected.Bottom - 1)),
            Side.left => new Point(selected.Left - 1, Math.Clamp(point.Y, selected.Top, selected.Bottom - 1)),
            Side.above => new Point(Math.Clamp(point.X, selected.Left, selected.Right - 1), selected.Top - 1),
            _ => new Point(Math.Clamp(point.X, selected.Left, selected.Right - 1), selected.Bottom)
        };
        return displays.Any(display => display != selected && display.Contains(outside));
    }

    internal static bool CanCross(Point point, Rectangle selected, IReadOnlyList<Rectangle> displays, Side side, int dx, int dy) =>
        Edge(point, selected, side, dx, dy) && !BoundaryBlocked(point, selected, displays, side);

    internal static bool CanStartCross(Point physicalPoint, Rectangle selected, IReadOnlyList<Rectangle> displays, Side side, int dx, int dy) =>
        selected.Contains(physicalPoint) && CanCross(physicalPoint, selected, displays, side, dx, dy);
}

public sealed class InputBridge : IDisposable {
    const ulong Marker = 0x53425247;
    const int RawInputMessage = 0x00FF;
    const int CommandMessage = 0x8001;
    const int MessageOnlyWindow = -3;

    readonly ConcurrentQueue<InputCommand> commands = new();
    readonly ManualResetEventSlim ready = new(false);
    readonly Thread inputThread;
    readonly HookProc mouseProc;
    readonly HookProc keyProc;
    readonly HashSet<int> injectedKeys = [];
    readonly HashSet<int> injectedButtons = [];
    readonly HashSet<int> outgoingButtons = [];
    readonly HashSet<int> physicalKeys = [];

    InputWindow? window;
    ApplicationContext? context;
    Exception? startupException;
    IntPtr mouseHook;
    IntPtr keyHook;
    int disposeRequested;
    bool connected;
    bool remote;
    bool receiving;
    bool cursorHidden;
    DateTime entered = DateTime.MinValue;
    Side side = Side.right;
    Rectangle bridgeBounds = Screen.PrimaryScreen?.Bounds ?? SystemInformation.VirtualScreen;
    Rectangle[] localDisplayBounds = Screen.AllScreens.Select(screen => screen.Bounds).ToArray();

    public Action<object>? Send;
    public Action<string>? Status;

    public InputBridge() {
        mouseProc = MouseHook;
        keyProc = KeyHook;
        inputThread = new Thread(InputThreadMain) {
            IsBackground = false,
            Name = "ScreenBridge input"
        };
        inputThread.SetApartmentState(ApartmentState.STA);
        inputThread.Start();
        if (!ready.Wait(TimeSpan.FromSeconds(5))) {
            Interlocked.Exchange(ref disposeRequested, 1);
            throw new TimeoutException("Timed out starting the input service");
        }
        if (startupException != null) throw new InvalidOperationException("Could not start the input service", startupException);
    }

    void InputThreadMain() {
        try {
            window = new InputWindow(this);
            window.Create();
            mouseHook = SetWindowsHookEx(14, mouseProc, GetModuleHandle(null), 0);
            keyHook = SetWindowsHookEx(13, keyProc, GetModuleHandle(null), 0);
            if (mouseHook == IntPtr.Zero || keyHook == IntPtr.Zero) throw new InvalidOperationException("Could not install input hooks");
            var device = new RAWINPUTDEVICE { UsagePage = 1, Usage = 2, Flags = 0x100, Target = window.Handle };
            if (!RegisterRawInputDevices([device], 1, (uint)Marshal.SizeOf<RAWINPUTDEVICE>()))
                throw new InvalidOperationException("Could not register mouse input");
            context = new ApplicationContext();
            ready.Set();
            Application.Run(context);
        } catch (Exception exception) {
            startupException = exception;
            Diagnostics.Write("input-thread", exception: exception);
            ready.Set();
        } finally {
            try {
                ReturnLocalCore(false);
                connected = false;
            } catch (Exception exception) {
                Diagnostics.Write("input-thread-release", exception: exception);
            }
            if (mouseHook != IntPtr.Zero) UnhookWindowsHookEx(mouseHook);
            if (keyHook != IntPtr.Zero) UnhookWindowsHookEx(keyHook);
            mouseHook = keyHook = IntPtr.Zero;
            window?.Destroy();
            window = null;
            CompletePending(new ObjectDisposedException(nameof(InputBridge)));
        }
    }

    Task Post(Action action, bool allowDuringDispose = false) {
        if ((!allowDuringDispose && Volatile.Read(ref disposeRequested) != 0) || window == null)
            return Task.FromException(new ObjectDisposedException(nameof(InputBridge)));
        var completion = new TaskCompletionSource(TaskCreationOptions.RunContinuationsAsynchronously);
        commands.Enqueue(new InputCommand(action, completion));
        if (!PostMessage(window.Handle, CommandMessage, IntPtr.Zero, IntPtr.Zero)) {
            completion.TrySetException(new InvalidOperationException("Could not post to the input service"));
        }
        return completion.Task;
    }

    void DrainCommands() {
        while (commands.TryDequeue(out var command)) {
            try {
                command.Action();
                command.Completion.TrySetResult();
            } catch (Exception exception) {
                command.Completion.TrySetException(exception);
            }
        }
    }

    void CompletePending(Exception exception) {
        while (commands.TryDequeue(out var command)) command.Completion.TrySetException(exception);
    }

    public Task ConfigureAsync(Side selectedSide, Rectangle selected, IEnumerable<Rectangle> displays) {
        var displaySnapshot = displays.Distinct().ToArray();
        return Post(() => {
            if (side != selectedSide || bridgeBounds != selected) ReturnLocalCore(false);
            side = selectedSide;
            bridgeBounds = selected;
            localDisplayBounds = displaySnapshot;
        });
    }

    public void Configure(Side selectedSide, Rectangle selected, IEnumerable<Rectangle> displays) =>
        Observe(ConfigureAsync(selectedSide, selected, displays), "configure-input");

    public void SetConnected(bool value) => Observe(Post(() => {
        connected = value;
        if (!value) ReturnLocalCore(false);
    }), "set-connected");

    public Task ReceiveAsync(JsonElement message) => Post(() => { if (connected) ReceiveCore(message); });

    public void ReturnLocal(bool notify, double? position = null) =>
        Observe(Post(() => ReturnLocalCore(notify, position)), "return-local");

    static async void Observe(Task task, string operation) {
        try { await task.ConfigureAwait(false); }
        catch (ObjectDisposedException) { }
        catch (Exception exception) { Diagnostics.Write(operation, exception: exception); }
    }

    Side Exit => side switch { Side.right => Side.left, Side.left => Side.right, Side.above => Side.below, _ => Side.above };

    static double Fraction(Point point, Rectangle bounds, Side edge) => Math.Clamp(
        edge is Side.right or Side.left
            ? (point.Y - bounds.Top) / (double)bounds.Height
            : (point.X - bounds.Left) / (double)bounds.Width,
        0,
        1);

    static Point EdgePoint(double fraction, Rectangle bounds, Side edge) {
        fraction = Math.Clamp(fraction, 0, 1);
        return edge switch {
            Side.left => new(bounds.Left + 1, bounds.Top + (int)(fraction * (bounds.Height - 1))),
            Side.right => new(bounds.Right - 2, bounds.Top + (int)(fraction * (bounds.Height - 1))),
            Side.above => new(bounds.Left + (int)(fraction * (bounds.Width - 1)), bounds.Top + 1),
            _ => new(bounds.Left + (int)(fraction * (bounds.Width - 1)), bounds.Bottom - 2)
        };
    }

    void Warp(Point point) {
        var desktop = SystemInformation.VirtualScreen;
        Inject(new INPUT {
            Type = 0,
            Data = new INPUTUNION {
                Mouse = new MOUSEINPUT {
                    Dx = (int)((point.X - desktop.Left) * 65535.0 / Math.Max(1, desktop.Width - 1)),
                    Dy = (int)((point.Y - desktop.Top) * 65535.0 / Math.Max(1, desktop.Height - 1)),
                    Flags = 0x8000 | 0x4000 | 1,
                    ExtraInfo = (UIntPtr)Marker
                }
            }
        });
    }

    void HideCursor() {
        if (cursorHidden) return;
        ShowCursor(false);
        cursorHidden = true;
    }

    void RestoreCursor() {
        if (!cursorHidden) return;
        ShowCursor(true);
        cursorHidden = false;
    }

    void ReturnLocalCore(bool notify, double? position = null) {
        if (remote) {
            remote = false;
            RestoreCursor();
            Warp(EdgePoint(position ?? 0.5, bridgeBounds, Exit));
        } else RestoreCursor();
        receiving = false;
        outgoingButtons.Clear();
        ReleaseInjected();
        entered = DateTime.UtcNow;
        if (notify && connected) Send?.Invoke(new { type = "release" });
        Status?.Invoke(connected ? "Connected · controlling this Windows PC" : "Not connected");
    }

    void RawInputCore(IntPtr handle) {
        try {
            uint length = 0;
            var header = (uint)Marshal.SizeOf<RAWINPUTHEADER>();
            GetRawInputData(handle, 0x10000003, IntPtr.Zero, ref length, header);
            if (length < header + 24 || length > 4096) return;
            var buffer = Marshal.AllocHGlobal((int)length);
            try {
                if (GetRawInputData(handle, 0x10000003, buffer, ref length, header) == uint.MaxValue) return;
                var rawHeader = Marshal.PtrToStructure<RAWINPUTHEADER>(buffer);
                if (rawHeader.Type != 0) return;
                var mouse = Marshal.PtrToStructure<RAWMOUSE>(buffer + (int)header);
                if ((mouse.Flags & 1) != 0) return;
                if (connected && remote && (mouse.LastX != 0 || mouse.LastY != 0))
                    Send?.Invoke(new { type = "move", dx = mouse.LastX, dy = mouse.LastY });
            } finally {
                Marshal.FreeHGlobal(buffer);
            }
        } catch (Exception exception) {
            Diagnostics.Write("raw-input", exception: exception);
        }
    }

    IntPtr MouseHook(int code, IntPtr message, IntPtr info) {
        try { return MouseHookCore(code, message, info); }
        catch (Exception exception) {
            Diagnostics.Write("mouse-hook", $"code={code};message={message.ToInt64()}", exception);
            return CallNextHookEx(mouseHook, code, message, info);
        }
    }

    IntPtr MouseHookCore(int code, IntPtr message, IntPtr info) {
        if (code < 0 || !connected) return CallNextHookEx(mouseHook, code, message, info);
        var mouse = Marshal.PtrToStructure<MSLLHOOKSTRUCT>(info);
        if (mouse.ExtraInfo.ToUInt64() == Marker) return CallNextHookEx(mouseHook, code, message, info);
        var kind = message.ToInt32();
        if ((mouse.Flags & 1) != 0) return CallNextHookEx(mouseHook, code, message, info);
        if (receiving) {
            ReturnLocalCore(true);
            return CallNextHookEx(mouseHook, code, message, info);
        }
        if (kind == 0x200) {
            if (remote) return (IntPtr)1;
            GetCursorPos(out var cursor);
            var dx = mouse.Point.X - cursor.X;
            var dy = mouse.Point.Y - cursor.Y;
            var point = new Point(mouse.Point.X, mouse.Point.Y);
            if (outgoingButtons.Count == 0 && (DateTime.UtcNow - entered).TotalMilliseconds > 350 &&
                DisplayPortal.CanStartCross(point, bridgeBounds, localDisplayBounds, Exit, dx, dy)) {
                var fraction = Fraction(point, bridgeBounds, Exit);
                remote = true;
                entered = DateTime.UtcNow;
                Send?.Invoke(new { type = "enter", position = fraction });
                foreach (var key in new[] { 16, 17, 18, 91 })
                    if ((GetAsyncKeyState(key) & 0x8000) != 0) Send?.Invoke(new { type = "key", key, down = true });
                Warp(EdgePoint(fraction, bridgeBounds, Exit));
                HideCursor();
                Status?.Invoke("Connected · controlling Mac");
                return (IntPtr)1;
            }
        }
        var button = kind switch {
            0x201 or 0x202 => 0,
            0x204 or 0x205 => 1,
            0x207 or 0x208 => 2,
            0x20B or 0x20C => ((mouse.MouseData >> 16) & 0xffff) == 1 ? 3 : 4,
            _ => -1
        };
        if (button >= 0) {
            var down = kind is 0x201 or 0x204 or 0x207 or 0x20B;
            if (down) outgoingButtons.Add(button); else outgoingButtons.Remove(button);
            if (remote) {
                Send?.Invoke(new { type = "button", button, down });
                return (IntPtr)1;
            }
        }
        if (remote && kind is 0x20A or 0x20E) {
            var delta = unchecked((short)(mouse.MouseData >> 16));
            Send?.Invoke(new { type = "scroll", dy = kind == 0x20A ? delta : 0, dx = kind == 0x20E ? delta : 0 });
            return (IntPtr)1;
        }
        return CallNextHookEx(mouseHook, code, message, info);
    }

    static int Normalize(int key) => key switch { 160 or 161 => 16, 162 or 163 => 17, 164 or 165 => 18, 92 => 91, _ => key };

    IntPtr KeyHook(int code, IntPtr message, IntPtr info) {
        try { return KeyHookCore(code, message, info); }
        catch (Exception exception) {
            Diagnostics.Write("key-hook", $"code={code};message={message.ToInt64()}", exception);
            return CallNextHookEx(keyHook, code, message, info);
        }
    }

    IntPtr KeyHookCore(int code, IntPtr message, IntPtr info) {
        if (code < 0 || !connected) return CallNextHookEx(keyHook, code, message, info);
        var key = Marshal.PtrToStructure<KBDLLHOOKSTRUCT>(info);
        if (key.ExtraInfo.ToUInt64() == Marker || (key.Flags & 0x10) != 0) return CallNextHookEx(keyHook, code, message, info);
        var down = message.ToInt32() is 0x100 or 0x104;
        var normalized = Normalize((int)key.Key);
        if (down) physicalKeys.Add(normalized); else physicalKeys.Remove(normalized);
        if (down && key.Key == 27 &&
            (physicalKeys.Contains(17) || (GetAsyncKeyState(17) & 0x8000) != 0) &&
            (physicalKeys.Contains(18) || (GetAsyncKeyState(18) & 0x8000) != 0)) {
            ReturnLocalCore(true);
            return (IntPtr)1;
        }
        if (receiving) return CallNextHookEx(keyHook, code, message, info);
        if (remote) {
            Send?.Invoke(new { type = "key", key = normalized, down });
            return (IntPtr)1;
        }
        return CallNextHookEx(keyHook, code, message, info);
    }

    void ReceiveCore(JsonElement message) {
        var type = message.GetProperty("type").GetString();
        var position = message.TryGetProperty("position", out var positionValue) ? positionValue.GetDouble() : 0.5;
        switch (type) {
            case "enter":
                if (remote) ReturnLocalCore(false);
                ReleaseInjected();
                RestoreCursor();
                receiving = true;
                entered = DateTime.UtcNow;
                Warp(EdgePoint(position, bridgeBounds, Exit));
                Status?.Invoke("Connected · Mac input controls Windows");
                break;
            case "reject":
                if (remote) ReturnLocalCore(false, position);
                break;
            case "release":
            case "return":
                ReturnLocalCore(false, position);
                break;
            case "move": {
                if (!receiving) break;
                var dx = (int)Math.Clamp(message.GetProperty("dx").GetDouble(), -32768, 32767);
                var dy = (int)Math.Clamp(message.GetProperty("dy").GetDouble(), -32768, 32767);
                GetCursorPos(out var cursor);
                var current = new Point(cursor.X, cursor.Y);
                var target = new Point(current.X + dx, current.Y + dy);
                if (injectedButtons.Count == 0 && bridgeBounds.Contains(current) &&
                    (DateTime.UtcNow - entered).TotalMilliseconds > 350 &&
                    DisplayPortal.CanCross(target, bridgeBounds, localDisplayBounds, Exit, dx, dy)) {
                    Send?.Invoke(new { type = "return", position = Fraction(target, bridgeBounds, Exit) });
                    receiving = false;
                    ReleaseInjected();
                    Status?.Invoke("Connected · controlling this Windows PC");
                    break;
                }
                Inject(new INPUT { Type = 0, Data = new INPUTUNION { Mouse = new MOUSEINPUT { Dx = dx, Dy = dy, Flags = 1, ExtraInfo = (UIntPtr)Marker } } });
                break;
            }
            case "key":
                if (receiving) Key(message.GetProperty("key").GetInt32(), message.GetProperty("down").GetBoolean());
                break;
            case "button":
                if (receiving) Button(message.GetProperty("button").GetInt32(), message.GetProperty("down").GetBoolean());
                break;
            case "scroll":
                if (!receiving) break;
                var vertical = message.GetProperty("dy").GetInt32();
                var horizontal = message.GetProperty("dx").GetInt32();
                if (vertical != 0) Wheel(vertical, 0x800);
                if (horizontal != 0) Wheel(horizontal, 0x1000);
                break;
        }
    }

    void Key(int virtualKey, bool down) {
        if (virtualKey is < 1 or > 255) return;
        if (down) injectedKeys.Add(virtualKey); else injectedKeys.Remove(virtualKey);
        var extended = virtualKey is 33 or 34 or 35 or 36 or 37 or 38 or 39 or 40 or 45 or 46 or 91 or 92 or 111;
        Inject(new INPUT {
            Type = 1,
            Data = new INPUTUNION {
                Keyboard = new KEYBDINPUT {
                    Vk = (ushort)virtualKey,
                    Flags = (down ? 0u : 2u) | (extended ? 1u : 0u),
                    ExtraInfo = (UIntPtr)Marker
                }
            }
        });
    }

    void Button(int button, bool down) {
        if (button is < 0 or > 4) return;
        Diagnostics.Write("remote-button", $"button={button};down={down}");
        if (down) injectedButtons.Add(button); else injectedButtons.Remove(button);
        var flags = button switch { 0 => down ? 2u : 4u, 1 => down ? 8u : 16u, 2 => down ? 32u : 64u, _ => down ? 128u : 256u };
        Inject(new INPUT {
            Type = 0,
            Data = new INPUTUNION {
                Mouse = new MOUSEINPUT {
                    Flags = flags,
                    MouseData = button == 3 ? 1u : button == 4 ? 2u : 0u,
                    ExtraInfo = (UIntPtr)Marker
                }
            }
        });
    }

    void Wheel(int delta, uint flag) => Inject(new INPUT {
        Type = 0,
        Data = new INPUTUNION {
            Mouse = new MOUSEINPUT { Flags = flag, MouseData = unchecked((uint)delta), ExtraInfo = (UIntPtr)Marker }
        }
    });

    void Inject(INPUT input) {
        if (SendInput(1, [input], Marshal.SizeOf<INPUT>()) == 1) return;
        var error = Marshal.GetLastWin32Error();
        Diagnostics.Write("send-input-failed", $"type={input.Type};error={error}");
        Status?.Invoke("Windows blocked input. Elevated apps and secure screens may need local control.");
    }

    void ReleaseInjected() {
        foreach (var key in injectedKeys.ToArray()) Key(key, false);
        foreach (var button in injectedButtons.ToArray()) Button(button, false);
    }

    public void Dispose() {
        if (Interlocked.Exchange(ref disposeRequested, 1) != 0) return;
        Observe(Post(() => {
            ReturnLocalCore(false);
            connected = false;
            context?.ExitThread();
        }, true), "dispose-input");
    }

    sealed record InputCommand(Action Action, TaskCompletionSource Completion);

    sealed class InputWindow(InputBridge owner) : NativeWindow {
        internal void Create() => CreateHandle(new CreateParams { Caption = "ScreenBridge Input", Parent = (IntPtr)MessageOnlyWindow });
        internal void Destroy() { if (Handle != IntPtr.Zero) DestroyHandle(); }

        protected override void WndProc(ref Message message) {
            if (message.Msg == CommandMessage) {
                owner.DrainCommands();
                return;
            }
            if (message.Msg == RawInputMessage) owner.RawInputCore(message.LParam);
            base.WndProc(ref message);
        }
    }

    delegate IntPtr HookProc(int code, IntPtr message, IntPtr info);
    [StructLayout(LayoutKind.Sequential)] struct POINT { public int X, Y; }
    [StructLayout(LayoutKind.Sequential)] struct MSLLHOOKSTRUCT { public POINT Point; public uint MouseData, Flags, Time; public UIntPtr ExtraInfo; }
    [StructLayout(LayoutKind.Sequential)] struct KBDLLHOOKSTRUCT { public uint Key, Scan, Flags, Time; public UIntPtr ExtraInfo; }
    [StructLayout(LayoutKind.Sequential)] struct RAWINPUTHEADER { public uint Type, Size; public IntPtr Device, WParam; }
    [StructLayout(LayoutKind.Explicit, Size = 24)] struct RAWMOUSE {
        [FieldOffset(0)] public ushort Flags;
        [FieldOffset(4)] public uint Buttons;
        [FieldOffset(8)] public uint RawButtons;
        [FieldOffset(12)] public int LastX;
        [FieldOffset(16)] public int LastY;
        [FieldOffset(20)] public uint Extra;
    }
    [StructLayout(LayoutKind.Sequential)] struct RAWINPUTDEVICE { public ushort UsagePage, Usage; public uint Flags; public IntPtr Target; }
    [StructLayout(LayoutKind.Sequential)] struct INPUT { public uint Type; public INPUTUNION Data; }
    [StructLayout(LayoutKind.Explicit)] struct INPUTUNION {
        [FieldOffset(0)] public MOUSEINPUT Mouse;
        [FieldOffset(0)] public KEYBDINPUT Keyboard;
    }
    [StructLayout(LayoutKind.Sequential)] struct MOUSEINPUT { public int Dx, Dy; public uint MouseData, Flags, Time; public UIntPtr ExtraInfo; }
    [StructLayout(LayoutKind.Sequential)] struct KEYBDINPUT { public ushort Vk, Scan; public uint Flags, Time; public UIntPtr ExtraInfo; }

    [DllImport("user32.dll")] static extern IntPtr SetWindowsHookEx(int kind, HookProc proc, IntPtr module, uint thread);
    [DllImport("user32.dll")] static extern bool UnhookWindowsHookEx(IntPtr hook);
    [DllImport("user32.dll")] static extern IntPtr CallNextHookEx(IntPtr hook, int code, IntPtr message, IntPtr info);
    [DllImport("kernel32.dll", CharSet = CharSet.Unicode)] static extern IntPtr GetModuleHandle(string? name);
    [DllImport("user32.dll")] static extern bool GetCursorPos(out POINT point);
    [DllImport("user32.dll")] static extern short GetAsyncKeyState(int key);
    [DllImport("user32.dll", SetLastError = true)] static extern uint SendInput(uint count, INPUT[] inputs, int size);
    [DllImport("user32.dll")] static extern bool RegisterRawInputDevices(RAWINPUTDEVICE[] devices, uint count, uint size);
    [DllImport("user32.dll")] static extern uint GetRawInputData(IntPtr handle, uint command, IntPtr data, ref uint length, uint header);
    [DllImport("user32.dll")] static extern bool PostMessage(IntPtr window, int message, IntPtr wParam, IntPtr lParam);
    [DllImport("user32.dll")] static extern int ShowCursor(bool show);
}
