using System.Drawing.Drawing2D;
using System.ComponentModel;
using System.Net;
using System.Net.Sockets;
using System.Security.Cryptography;
using System.Text.Json;

namespace ScreenBridge;

static class Theme {
    public static readonly Color Window = Color.FromArgb(12, 16, 24);
    public static readonly Color Surface = Color.FromArgb(20, 27, 39);
    public static readonly Color SurfaceRaised = Color.FromArgb(27, 36, 51);
    public static readonly Color SurfaceHover = Color.FromArgb(35, 46, 64);
    public static readonly Color Input = Color.FromArgb(14, 20, 30);
    public static readonly Color Border = Color.FromArgb(52, 67, 89);
    public static readonly Color BorderSoft = Color.FromArgb(37, 48, 65);
    public static readonly Color Text = Color.FromArgb(244, 247, 252);
    public static readonly Color Muted = Color.FromArgb(160, 171, 190);
    public static readonly Color Subtle = Color.FromArgb(106, 121, 145);
    public static readonly Color Blue = Color.FromArgb(72, 140, 255);
    public static readonly Color Teal = Color.FromArgb(55, 211, 193);
    public static readonly Color Green = Color.FromArgb(86, 220, 156);
    public static readonly Color Amber = Color.FromArgb(247, 190, 87);
    public static readonly Color Red = Color.FromArgb(247, 112, 128);

    public static GraphicsPath Rounded(RectangleF rect, float radius) {
        var path = new GraphicsPath();
        var diameter = Math.Min(radius * 2, Math.Min(rect.Width, rect.Height));
        var arc = new RectangleF(rect.X, rect.Y, diameter, diameter);
        path.AddArc(arc, 180, 90);
        arc.X = rect.Right - diameter;
        path.AddArc(arc, 270, 90);
        arc.Y = rect.Bottom - diameter;
        path.AddArc(arc, 0, 90);
        arc.X = rect.Left;
        path.AddArc(arc, 90, 90);
        path.CloseFigure();
        return path;
    }

    public static Color Mix(Color from, Color to, float amount) {
        amount = Math.Clamp(amount, 0, 1);
        return Color.FromArgb(
            (int)(from.A + (to.A - from.A) * amount),
            (int)(from.R + (to.R - from.R) * amount),
            (int)(from.G + (to.G - from.G) * amount),
            (int)(from.B + (to.B - from.B) * amount));
    }
}

sealed class BrandMark : Control {
    static readonly Lazy<Image?> Logo = new(LoadLogo);

    public BrandMark() {
        SetStyle(ControlStyles.AllPaintingInWmPaint | ControlStyles.OptimizedDoubleBuffer | ControlStyles.UserPaint | ControlStyles.SupportsTransparentBackColor, true);
        BackColor = Color.Transparent;
    }

    protected override void OnPaint(PaintEventArgs e) {
        if (Logo.Value != null) {
            e.Graphics.InterpolationMode = InterpolationMode.HighQualityBicubic;
            e.Graphics.PixelOffsetMode = PixelOffsetMode.HighQuality;
            e.Graphics.DrawImage(Logo.Value, new Rectangle(0, 0, Width, Height));
            return;
        }
        e.Graphics.SmoothingMode = SmoothingMode.AntiAlias;
        var rect = new RectangleF(1, 1, Width - 2, Height - 2);
        using var path = Theme.Rounded(rect, 13);
        using var gradient = new LinearGradientBrush(rect, Theme.Blue, Theme.Teal, 35f);
        e.Graphics.FillPath(gradient, path);
        using var arrow = new Pen(Color.White, 3) { StartCap = LineCap.Round, EndCap = LineCap.ArrowAnchor };
        e.Graphics.DrawLine(arrow, rect.Left + 10, rect.Top + rect.Height / 2, rect.Right - 10, rect.Top + rect.Height / 2);
    }

    static Image? LoadLogo() {
        try {
            var assembly = typeof(BrandMark).Assembly;
            var name = assembly.GetManifestResourceNames().FirstOrDefault(value => value.EndsWith("logo-128.png", StringComparison.Ordinal));
            if (name == null) return null;
            using var stream = assembly.GetManifestResourceStream(name);
            if (stream == null) return null;
            using var loaded = new Bitmap(stream);
            return new Bitmap(loaded);
        } catch { return null; }
    }
}

enum ButtonKind { Primary, Secondary, Quiet }

sealed class ModernButton : Button {
    bool hot;
    bool pressed;
    [DefaultValue(ButtonKind.Secondary)]
    public ButtonKind Kind { get; set; } = ButtonKind.Secondary;

    public ModernButton() {
        SetStyle(ControlStyles.AllPaintingInWmPaint | ControlStyles.OptimizedDoubleBuffer | ControlStyles.UserPaint | ControlStyles.ResizeRedraw, true);
        FlatStyle = FlatStyle.Flat;
        FlatAppearance.BorderSize = 0;
        UseVisualStyleBackColor = false;
        Cursor = Cursors.Hand;
        Font = new Font("Segoe UI", 9.5f, FontStyle.Bold);
        ForeColor = Theme.Text;
        TabStop = true;
    }

    protected override void OnMouseEnter(EventArgs e) { hot = true; Invalidate(); base.OnMouseEnter(e); }
    protected override void OnMouseLeave(EventArgs e) { hot = pressed = false; Invalidate(); base.OnMouseLeave(e); }
    protected override void OnMouseDown(MouseEventArgs e) { if (e.Button == MouseButtons.Left) pressed = true; Invalidate(); base.OnMouseDown(e); }
    protected override void OnMouseUp(MouseEventArgs e) { pressed = false; Invalidate(); base.OnMouseUp(e); }
    protected override void OnEnabledChanged(EventArgs e) { Invalidate(); base.OnEnabledChanged(e); }

    protected override void OnPaint(PaintEventArgs e) {
        e.Graphics.SmoothingMode = SmoothingMode.AntiAlias;
        e.Graphics.Clear(Parent?.BackColor ?? Theme.Window);
        var rect = new RectangleF(1, 1, Width - 3, Height - 3);
        using var path = Theme.Rounded(rect, 10);

        Color fill;
        Color border;
        if (Kind == ButtonKind.Primary) {
            fill = Theme.Teal;
            border = Theme.Mix(Theme.Teal, Color.White, .18f);
        } else if (Kind == ButtonKind.Quiet) {
            fill = Theme.Surface;
            border = Theme.BorderSoft;
        } else {
            fill = Theme.SurfaceRaised;
            border = Theme.Border;
        }
        if (hot) fill = Theme.Mix(fill, Color.White, .08f);
        if (pressed) fill = Theme.Mix(fill, Color.Black, .13f);
        if (!Enabled) { fill = Theme.Mix(fill, Theme.Window, .45f); border = Theme.BorderSoft; }

        if (Kind == ButtonKind.Primary) {
            using var gradient = new LinearGradientBrush(rect, Theme.Mix(fill, Theme.Blue, .18f), fill, 12f);
            e.Graphics.FillPath(gradient, path);
        } else {
            using var brush = new SolidBrush(fill);
            e.Graphics.FillPath(brush, path);
        }
        using var pen = new Pen(Focused ? Theme.Blue : border, Focused ? 1.6f : 1f);
        e.Graphics.DrawPath(pen, path);

        var textColor = Enabled ? (Kind == ButtonKind.Primary ? Theme.Window : Theme.Text) : Theme.Subtle;
        TextRenderer.DrawText(e.Graphics, Text, Font, ClientRectangle, textColor,
            TextFormatFlags.HorizontalCenter | TextFormatFlags.VerticalCenter | TextFormatFlags.SingleLine | TextFormatFlags.EndEllipsis);
    }
}

sealed class RoundedPanel : Panel {
    [DefaultValue(16)]
    public int Radius { get; set; } = 16;

    public RoundedPanel() {
        SetStyle(ControlStyles.AllPaintingInWmPaint | ControlStyles.OptimizedDoubleBuffer | ControlStyles.UserPaint | ControlStyles.ResizeRedraw | ControlStyles.SupportsTransparentBackColor, true);
        BackColor = Theme.Surface;
    }

    protected override void OnResize(EventArgs eventargs) {
        base.OnResize(eventargs);
        if (Width <= 1 || Height <= 1) return;
        using var path = Theme.Rounded(new RectangleF(0, 0, Width, Height), Radius);
        Region?.Dispose();
        Region = new Region(path);
    }

    protected override void OnPaintBackground(PaintEventArgs e) {
        e.Graphics.SmoothingMode = SmoothingMode.AntiAlias;
        e.Graphics.Clear(Parent?.BackColor ?? Theme.Window);
        using var path = Theme.Rounded(new RectangleF(.5f, .5f, Width - 1, Height - 1), Radius);
        using var fill = new SolidBrush(BackColor);
        e.Graphics.FillPath(fill, path);
    }

    protected override void OnPaint(PaintEventArgs e) {
        base.OnPaint(e);
        e.Graphics.SmoothingMode = SmoothingMode.AntiAlias;
        using var path = Theme.Rounded(new RectangleF(.5f, .5f, Width - 1, Height - 1), Radius);
        using var border = new Pen(Theme.BorderSoft, 1);
        e.Graphics.DrawPath(border, path);
    }
}

sealed class ReadonlyField : Panel {
    readonly TextBox inner = new();

    [DesignerSerializationVisibility(DesignerSerializationVisibility.Hidden)]
    public string Value {
        get => inner.Text;
        set => inner.Text = value;
    }

    public ReadonlyField() {
        SetStyle(ControlStyles.AllPaintingInWmPaint | ControlStyles.OptimizedDoubleBuffer | ControlStyles.UserPaint | ControlStyles.ResizeRedraw, true);
        BackColor = Theme.Input;
        inner.ReadOnly = true;
        inner.BorderStyle = BorderStyle.None;
        inner.BackColor = Theme.Input;
        inner.ForeColor = Theme.Text;
        inner.Font = new Font("Segoe UI Semibold", 11f, FontStyle.Regular);
        inner.TabStop = true;
        Controls.Add(inner);
    }

    protected override void OnResize(EventArgs eventargs) {
        base.OnResize(eventargs);
        inner.Bounds = new Rectangle(15, Math.Max(8, (Height - inner.PreferredHeight) / 2), Math.Max(10, Width - 30), inner.PreferredHeight);
        using var path = Theme.Rounded(new RectangleF(0, 0, Width, Height), 10);
        Region?.Dispose();
        Region = new Region(path);
    }

    protected override void OnPaint(PaintEventArgs e) {
        base.OnPaint(e);
        e.Graphics.SmoothingMode = SmoothingMode.AntiAlias;
        using var path = Theme.Rounded(new RectangleF(.5f, .5f, Width - 1, Height - 1), 10);
        using var pen = new Pen(Theme.Border, 1);
        e.Graphics.DrawPath(pen, path);
    }
}

sealed class StatusPill : Control {
    string caption = "STARTING";
    Color tone = Theme.Subtle;

    public void Set(string text, Color color) {
        caption = text.ToUpperInvariant();
        tone = color;
        Invalidate();
    }

    public StatusPill() {
        SetStyle(ControlStyles.AllPaintingInWmPaint | ControlStyles.OptimizedDoubleBuffer | ControlStyles.UserPaint | ControlStyles.SupportsTransparentBackColor, true);
        BackColor = Color.Transparent;
        Font = new Font("Segoe UI", 8.5f, FontStyle.Bold);
    }

    protected override void OnPaint(PaintEventArgs e) {
        e.Graphics.SmoothingMode = SmoothingMode.AntiAlias;
        var rect = new RectangleF(1, 1, Width - 3, Height - 3);
        using var path = Theme.Rounded(rect, Height / 2f);
        using var fill = new SolidBrush(Color.FromArgb(24, tone));
        using var border = new Pen(Color.FromArgb(95, tone), 1);
        e.Graphics.FillPath(fill, path);
        e.Graphics.DrawPath(border, path);
        using var dot = new SolidBrush(tone);
        e.Graphics.FillEllipse(dot, 13, Height / 2f - 3, 6, 6);
        TextRenderer.DrawText(e.Graphics, caption, Font, new Rectangle(26, 0, Width - 34, Height), Theme.Text,
            TextFormatFlags.Left | TextFormatFlags.VerticalCenter | TextFormatFlags.SingleLine | TextFormatFlags.EndEllipsis);
    }
}

sealed class StatusBanner : Control {
    string message = "Starting ScreenBridge…";
    Color tone = Theme.Subtle;

    public void Set(string text, Color color) {
        message = text;
        tone = color;
        Invalidate();
    }

    public StatusBanner() {
        SetStyle(ControlStyles.AllPaintingInWmPaint | ControlStyles.OptimizedDoubleBuffer | ControlStyles.UserPaint | ControlStyles.ResizeRedraw, true);
        BackColor = Theme.Surface;
        Font = new Font("Segoe UI", 9.25f, FontStyle.Bold);
    }

    protected override void OnPaint(PaintEventArgs e) {
        e.Graphics.SmoothingMode = SmoothingMode.AntiAlias;
        var rect = new RectangleF(.5f, .5f, Width - 1, Height - 1);
        using var path = Theme.Rounded(rect, 11);
        using var fill = new SolidBrush(Theme.Surface);
        using var border = new Pen(Theme.BorderSoft, 1);
        e.Graphics.FillPath(fill, path);
        e.Graphics.DrawPath(border, path);
        using var barPath = Theme.Rounded(new RectangleF(10, 9, 4, Height - 18), 2);
        using var accent = new SolidBrush(tone);
        e.Graphics.FillPath(accent, barPath);
        TextRenderer.DrawText(e.Graphics, message, Font, new Rectangle(27, 0, Width - 42, Height), Theme.Text,
            TextFormatFlags.Left | TextFormatFlags.VerticalCenter | TextFormatFlags.SingleLine | TextFormatFlags.EndEllipsis);
    }
}

sealed class SidePicker : Control {
    static readonly Side[] Options = [Side.left, Side.right, Side.above, Side.below];
    static readonly string[] Names = ["LEFT", "RIGHT", "ABOVE", "BELOW"];
    int hot = -1;
    Side selected = Side.right;
    public Action<Side>? Changed;

    [DesignerSerializationVisibility(DesignerSerializationVisibility.Hidden)]
    public Side SelectedSide {
        get => selected;
        set { selected = value; Invalidate(); }
    }

    public SidePicker() {
        SetStyle(ControlStyles.AllPaintingInWmPaint | ControlStyles.OptimizedDoubleBuffer | ControlStyles.UserPaint | ControlStyles.ResizeRedraw | ControlStyles.Selectable, true);
        BackColor = Theme.Surface;
        Font = new Font("Segoe UI", 8f, FontStyle.Bold);
        Cursor = Cursors.Hand;
        TabStop = true;
    }

    int IndexAt(Point p) => p.X < 0 || p.Y < 0 || p.X >= Width || p.Y >= Height ? -1 : Math.Min(3, p.X * 4 / Math.Max(1, Width));
    protected override void OnMouseMove(MouseEventArgs e) { var next = IndexAt(e.Location); if (next != hot) { hot = next; Invalidate(); } base.OnMouseMove(e); }
    protected override void OnMouseLeave(EventArgs e) { hot = -1; Invalidate(); base.OnMouseLeave(e); }
    protected override void OnMouseDown(MouseEventArgs e) { Focus(); var i = IndexAt(e.Location); if (i >= 0) { selected = Options[i]; Changed?.Invoke(selected); Invalidate(); } base.OnMouseDown(e); }
    protected override void OnKeyDown(KeyEventArgs e) {
        var i = Array.IndexOf(Options, selected);
        if (e.KeyCode is Keys.Left or Keys.Up) i = (i + 3) % 4;
        else if (e.KeyCode is Keys.Right or Keys.Down) i = (i + 1) % 4;
        else { base.OnKeyDown(e); return; }
        selected = Options[i]; Changed?.Invoke(selected); Invalidate(); e.Handled = true;
    }

    protected override void OnPaint(PaintEventArgs e) {
        e.Graphics.SmoothingMode = SmoothingMode.AntiAlias;
        var outer = new RectangleF(.5f, .5f, Width - 1, Height - 1);
        using var outerPath = Theme.Rounded(outer, 10);
        using var fill = new SolidBrush(Theme.Surface);
        using var border = new Pen(Focused ? Theme.Blue : Theme.BorderSoft, 1);
        e.Graphics.FillPath(fill, outerPath);
        e.Graphics.DrawPath(border, outerPath);
        var cell = Width / 4f;
        for (var i = 0; i < 4; i++) {
            var active = Options[i] == selected;
            var r = new RectangleF(i * cell + 3, 3, cell - 6, Height - 6);
            if (active || hot == i) {
                using var itemPath = Theme.Rounded(r, 8);
                using var itemFill = new SolidBrush(active ? Color.FromArgb(35, Theme.Teal) : Theme.SurfaceHover);
                e.Graphics.FillPath(itemFill, itemPath);
                if (active) {
                    using var itemBorder = new Pen(Color.FromArgb(120, Theme.Teal), 1);
                    e.Graphics.DrawPath(itemBorder, itemPath);
                }
            }
            TextRenderer.DrawText(e.Graphics, Names[i], Font, Rectangle.Round(r), active ? Theme.Teal : Theme.Muted,
                TextFormatFlags.HorizontalCenter | TextFormatFlags.VerticalCenter | TextFormatFlags.SingleLine);
        }
    }
}

sealed record BridgeDisplay(string Id, string Name, int X, int Y, int Width, int Height, bool Primary) {
    public Rectangle Bounds => new(X, Y, Width, Height);
}

sealed class LayoutPanel : Panel {
    [Browsable(false), DesignerSerializationVisibility(DesignerSerializationVisibility.Hidden)]
    public Side Side { get; set; } = Side.right;
    [Browsable(false), DesignerSerializationVisibility(DesignerSerializationVisibility.Hidden)]
    public BridgeDisplay[] MacDisplays { get; set; } = [];
    [Browsable(false), DesignerSerializationVisibility(DesignerSerializationVisibility.Hidden)]
    public BridgeDisplay[] WindowsDisplays { get; set; } = [];
    [Browsable(false), DesignerSerializationVisibility(DesignerSerializationVisibility.Hidden)]
    public string? SelectedMacDisplay { get; set; }
    [Browsable(false), DesignerSerializationVisibility(DesignerSerializationVisibility.Hidden)]
    public string? SelectedWindowsDisplay { get; set; }
    [Browsable(false), DesignerSerializationVisibility(DesignerSerializationVisibility.Hidden)]
    public Action<Side, string?, string?, bool>? Changed { get; set; }
    bool dragging;
    readonly Dictionary<string, RectangleF> macDisplayHits = new(StringComparer.Ordinal);
    readonly Dictionary<string, RectangleF> windowsDisplayHits = new(StringComparer.Ordinal);

    public LayoutPanel() {
        SetStyle(ControlStyles.AllPaintingInWmPaint | ControlStyles.OptimizedDoubleBuffer | ControlStyles.UserPaint | ControlStyles.ResizeRedraw, true);
        BackColor = Theme.Surface;
    }

    PointF Center => new(Width / 2f, Height / 2f + 9);
    PointF WinCenter => Side switch {
        Side.right => new(Center.X + 178, Center.Y),
        Side.left => new(Center.X - 178, Center.Y),
        Side.above => new(Center.X, Center.Y - 78),
        _ => new(Center.X, Center.Y + 78)
    };
    RectangleF WinRect => new(WinCenter.X - 84, WinCenter.Y - 40, 168, 80);

    protected override void OnResize(EventArgs eventargs) {
        base.OnResize(eventargs);
        if (Width <= 1 || Height <= 1) return;
        using var path = Theme.Rounded(new RectangleF(0, 0, Width, Height), 18);
        Region?.Dispose();
        Region = new Region(path);
    }

    protected override void OnPaint(PaintEventArgs e) {
        e.Graphics.SmoothingMode = SmoothingMode.AntiAlias;
        e.Graphics.Clear(Theme.Surface);

        using (var canvas = Theme.Rounded(new RectangleF(.5f, .5f, Width - 1, Height - 1), 18)) {
            using var background = new LinearGradientBrush(ClientRectangle, Theme.Surface, Color.FromArgb(17, 25, 37), 90f);
            e.Graphics.FillPath(background, canvas);
            e.Graphics.SetClip(canvas);
            using var grid = new Pen(Color.FromArgb(18, 125, 147, 176), 1);
            for (var x = 24; x < Width; x += 32) e.Graphics.DrawLine(grid, x, 0, x, Height);
            for (var y = 24; y < Height; y += 32) e.Graphics.DrawLine(grid, 0, y, Width, y);
            e.Graphics.ResetClip();
            using var border = new Pen(Theme.BorderSoft, 1);
            e.Graphics.DrawPath(border, canvas);
        }

        TextRenderer.DrawText(e.Graphics, "DRAG WINDOWS TO MATCH YOUR DESK", new Font("Segoe UI", 7.5f, FontStyle.Bold),
            new Rectangle(18, 14, 280, 20), Theme.Subtle, TextFormatFlags.Left | TextFormatFlags.VerticalCenter | TextFormatFlags.SingleLine);
        TextRenderer.DrawText(e.Graphics, $"WINDOWS {Side.ToString().ToUpperInvariant()}", new Font("Segoe UI", 7.5f, FontStyle.Bold),
            new Rectangle(Width - 170, 14, 150, 20), Theme.Teal, TextFormatFlags.Right | TextFormatFlags.VerticalCenter | TextFormatFlags.SingleLine);

        using var connection = new Pen(Color.FromArgb(150, Theme.Teal), 3) { StartCap = LineCap.Round, EndCap = LineCap.Round };
        e.Graphics.DrawLine(connection, Center, WinCenter);
        macDisplayHits.Clear();
        windowsDisplayHits.Clear();
        Card(e.Graphics, Center, "Mac", "REMOTE", Theme.Blue, false, MacDisplays, SelectedMacDisplay, macDisplayHits);
        Card(e.Graphics, WinCenter, "Windows", "THIS PC", Theme.Teal, true, WindowsDisplays, SelectedWindowsDisplay, windowsDisplayHits);
    }

    static void Card(Graphics g, PointF point, string name, string eyebrow, Color color, bool active,
        IReadOnlyList<BridgeDisplay> displays, string? selectedId, Dictionary<string, RectangleF> hits) {
        var rect = new RectangleF(point.X - 84, point.Y - 40, 168, 80);
        using var shadowPath = Theme.Rounded(new RectangleF(rect.X + 3, rect.Y + 5, rect.Width, rect.Height), 13);
        using var shadow = new SolidBrush(Color.FromArgb(80, 0, 0, 0));
        g.FillPath(shadow, shadowPath);
        using var path = Theme.Rounded(rect, 13);
        using var fill = new LinearGradientBrush(rect, Color.FromArgb(active ? 52 : 38, color), Theme.SurfaceRaised, 20f);
        using var border = new Pen(Color.FromArgb(active ? 230 : 170, color), active ? 2f : 1.5f);
        g.FillPath(fill, path);
        g.DrawPath(border, path);
        using var dot = new SolidBrush(color);
        g.FillEllipse(dot, rect.X + 14, rect.Y + 15, 7, 7);
        TextRenderer.DrawText(g, eyebrow, new Font("Segoe UI", 7f, FontStyle.Bold), new Rectangle((int)rect.X + 27, (int)rect.Y + 7, 124, 17), Theme.Subtle,
            TextFormatFlags.Left | TextFormatFlags.VerticalCenter | TextFormatFlags.SingleLine);
        TextRenderer.DrawText(g, name, new Font("Segoe UI", 10f, FontStyle.Bold), new Rectangle((int)rect.X + 14, (int)rect.Y + 22, 140, 20), Theme.Text,
            TextFormatFlags.Left | TextFormatFlags.VerticalCenter | TextFormatFlags.SingleLine);

        if (displays.Count == 0) {
            TextRenderer.DrawText(g, "Waiting for displays", new Font("Segoe UI", 7f), new Rectangle((int)rect.X + 12, (int)rect.Y + 47, 144, 20), Theme.Subtle,
                TextFormatFlags.HorizontalCenter | TextFormatFlags.VerticalCenter | TextFormatFlags.SingleLine);
            return;
        }

        var shown = displays.Take(4).ToArray();
        var gap = 4f;
        var tileWidth = (rect.Width - 24 - gap * (shown.Length - 1)) / shown.Length;
        for (var index = 0; index < shown.Length; index++) {
            var display = shown[index];
            var tile = new RectangleF(rect.X + 12 + index * (tileWidth + gap), rect.Y + 47, tileWidth, 22);
            hits[display.Id] = tile;
            var selected = display.Id == selectedId;
            using var tilePath = Theme.Rounded(tile, 5);
            using var tileFill = new SolidBrush(selected ? Color.FromArgb(65, color) : Theme.Input);
            using var tileBorder = new Pen(selected ? color : Theme.BorderSoft, selected ? 1.5f : 1f);
            g.FillPath(tileFill, tilePath);
            g.DrawPath(tileBorder, tilePath);
            var label = display.Primary ? $"{index + 1} •" : (index + 1).ToString();
            TextRenderer.DrawText(g, label, new Font("Segoe UI", 7f, FontStyle.Bold), Rectangle.Round(tile), selected ? Theme.Text : Theme.Muted,
                TextFormatFlags.HorizontalCenter | TextFormatFlags.VerticalCenter | TextFormatFlags.SingleLine);
        }
    }

    protected override void OnMouseDown(MouseEventArgs e) {
        var macHit = macDisplayHits.FirstOrDefault(item => item.Value.Contains(e.Location));
        if (!string.IsNullOrEmpty(macHit.Key)) {
            SelectedMacDisplay = macHit.Key;
            Changed?.Invoke(Side, SelectedMacDisplay, SelectedWindowsDisplay, false);
            Invalidate();
            return;
        }
        var windowsHit = windowsDisplayHits.FirstOrDefault(item => item.Value.Contains(e.Location));
        if (!string.IsNullOrEmpty(windowsHit.Key)) {
            SelectedWindowsDisplay = windowsHit.Key;
            Changed?.Invoke(Side, SelectedMacDisplay, SelectedWindowsDisplay, false);
            Invalidate();
            return;
        }
        dragging = WinRect.Contains(e.Location);
        Capture = dragging;
        if (dragging) Cursor = Cursors.SizeAll;
        base.OnMouseDown(e);
    }

    protected override void OnMouseMove(MouseEventArgs e) {
        if (dragging) {
            var dx = e.X - Center.X;
            var dy = e.Y - Center.Y;
            Side = Math.Abs(dx) > Math.Abs(dy) ? (dx > 0 ? Side.right : Side.left) : (dy > 0 ? Side.below : Side.above);
            Invalidate();
        } else Cursor = WinRect.Contains(e.Location) ? Cursors.Hand : Cursors.Default;
        base.OnMouseMove(e);
    }

    protected override void OnMouseUp(MouseEventArgs e) {
        if (dragging) Changed?.Invoke(Side, SelectedMacDisplay, SelectedWindowsDisplay, true);
        dragging = false;
        Capture = false;
        Cursor = WinRect.Contains(e.Location) ? Cursors.Hand : Cursors.Default;
        base.OnMouseUp(e);
    }
}

sealed class MainForm : Form {
    readonly LayoutPanel layout = new();
    readonly StatusBanner status = new();
    readonly StatusPill statusPill = new();
    readonly ModernButton listen = new(), copy = new();
    readonly SidePicker position = new();
    readonly ReadonlyField pairing = new();
    readonly RemoteInputBuffer<Link> remoteInputBuffer = new();
    readonly SemaphoreSlim remoteInputSerial = new(1, 1);
    readonly BridgeDisplay[] windowsDisplays = EnumerateLocalDisplays();
    BridgeDisplay[] macDisplays = [];
    InputBridge? input;
    TcpListener? listener;
    Link? link;
    string pairingCode = PairingCode.Create();
    int failedPairingAttempts;
    DateTime cooldownUntilUtc = DateTime.MinValue;
    bool listening;
    string StateFile => Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "ScreenBridge", "layout.txt");

    public MainForm() {
        SuspendLayout();
        Text = "ScreenBridge";
        try { Icon = Icon.ExtractAssociatedIcon(Application.ExecutablePath); } catch { }
        ClientSize = new Size(760, 740);
        MinimumSize = MaximumSize = new Size(776, 779);
        StartPosition = FormStartPosition.CenterScreen;
        BackColor = Theme.Window;
        ForeColor = Theme.Text;
        Font = new Font("Segoe UI", 9.5f);
        FormBorderStyle = FormBorderStyle.FixedSingle;
        MaximizeBox = false;
        AutoScaleMode = AutoScaleMode.Dpi;
        AutoScaleDimensions = new SizeF(96, 96);
        DoubleBuffered = true;
        KeyPreview = true;

        var mark = new BrandMark { Bounds = new Rectangle(38, 30, 46, 46) };
        Controls.Add(mark);
        AddLabel("ScreenBridge", 22f, FontStyle.Bold, new Rectangle(98, 27, 420, 37), Theme.Text);
        AddLabel("Two computers. One flow.", 9.5f, FontStyle.Regular, new Rectangle(100, 65, 430, 23), Theme.Muted);
        statusPill.Bounds = new Rectangle(600, 36, 122, 32);
        Controls.Add(statusPill);

        AddLabel("ARRANGE YOUR SCREENS", 8.5f, FontStyle.Bold, new Rectangle(38, 111, 260, 22), Theme.Muted);
        AddLabel("Drag the Windows card or choose a side.", 8.5f, FontStyle.Regular, new Rectangle(424, 111, 298, 22), Theme.Subtle, ContentAlignment.MiddleRight);
        layout.Bounds = new Rectangle(38, 142, 684, 246);
        layout.WindowsDisplays = windowsDisplays;
        layout.SelectedWindowsDisplay = DefaultDisplay(windowsDisplays, Opposite(layout.Side));
        layout.Changed = (side, macDisplay, windowsDisplay, resetDefaults) =>
            SetBridgeLayout(side, macDisplay, windowsDisplay, true, false, resetDefaults);
        Controls.Add(layout);

        AddLabel("Place Windows where it physically sits relative to your Mac.", 8.5f, FontStyle.Regular, new Rectangle(38, 400, 390, 34), Theme.Muted);
        position.Bounds = new Rectangle(440, 399, 282, 36);
        position.Changed = side => SetBridgeLayout(side, null, null, true, false, true);
        Controls.Add(position);

        AddLabel("CONNECT FROM YOUR MAC", 8.5f, FontStyle.Bold, new Rectangle(38, 455, 260, 22), Theme.Muted);
        var connectCard = new RoundedPanel { Bounds = new Rectangle(38, 482, 684, 112), Radius = 16 };
        connectCard.Controls.Add(NewLabel("THIS WINDOWS PC", 8f, FontStyle.Bold, new Rectangle(20, 14, 250, 19), Theme.Subtle));
        connectCard.Controls.Add(NewLabel("PAIRING CODE", 8f, FontStyle.Bold, new Rectangle(298, 14, 190, 19), Theme.Subtle));
        var addresses = Dns.GetHostAddresses(Dns.GetHostName())
            .Where(address => address.AddressFamily == AddressFamily.InterNetwork && !IPAddress.IsLoopback(address))
            .OrderBy(AddressPriority)
            .Select(address => address.ToString())
            .Distinct()
            .ToArray();
        var primaryAddress = addresses.FirstOrDefault() ?? "No local IPv4 address found";
        var address = new ReadonlyField { Bounds = new Rectangle(20, 39, 260, 43), Value = primaryAddress };
        connectCard.Controls.Add(address);
        pairing.Bounds = new Rectangle(298, 39, 190, 43);
        pairing.Value = pairingCode;
        connectCard.Controls.Add(pairing);
        copy.Text = "Copy code";
        copy.Kind = ButtonKind.Primary;
        copy.Bounds = new Rectangle(506, 39, 158, 43);
        copy.Click += (_, _) => {
            try {
                Clipboard.SetText(pairingCode);
                SetStatus("Short pairing code copied · you can also type it on the Mac");
            } catch {
                SetStatus("Could not access the clipboard · type the visible code on the Mac", true);
            }
        };
        connectCard.Controls.Add(copy);
        var alternate = addresses.Skip(1).ToArray();
        var hint = alternate.Length == 0
            ? "Type the visible 10-character code on your Mac. It changes after repeated failures."
            : "Type the code on Mac  ·  Other addresses: " + string.Join("  ·  ", alternate);
        connectCard.Controls.Add(NewLabel(hint, 8f, FontStyle.Regular, new Rectangle(20, 86, 644, 18), Theme.Subtle));
        Controls.Add(connectCard);

        listen.Text = "Stop listening";
        listen.Kind = ButtonKind.Secondary;
        listen.Bounds = new Rectangle(38, 612, 210, 42);
        listen.Click += (_, _) => { if (listening) Stop(); else Start(); };
        Controls.Add(listen);
        var local = new ModernButton { Text = "Return control", Kind = ButtonKind.Secondary, Bounds = new Rectangle(260, 612, 210, 42) };
        local.Click += (_, _) => input?.ReturnLocal(true);
        Controls.Add(local);
        var reset = new ModernButton { Text = "New pairing code", Kind = ButtonKind.Quiet, Bounds = new Rectangle(482, 612, 240, 42) };
        reset.Click += (_, _) => {
            link?.Dispose();
            input?.ReturnLocal(false);
            failedPairingAttempts = 0;
            cooldownUntilUtc = DateTime.MinValue;
            RotatePairingCode();
            SetStatus("New short pairing code created · type it on the Mac");
        };
        Controls.Add(reset);

        status.Bounds = new Rectangle(38, 670, 684, 40);
        Controls.Add(status);
        AddLabel("Emergency return: Ctrl + Alt + Escape", 8f, FontStyle.Regular, new Rectangle(38, 715, 330, 18), Theme.Subtle);
        AddLabel("Encrypted locally · clipboard and files are never shared", 8f, FontStyle.Regular, new Rectangle(360, 715, 362, 18), Theme.Subtle, ContentAlignment.MiddleRight);

        Shown += (_, _) => {
            try {
                input = new InputBridge();
                Diagnostics.Write("input-hooks-ready");
                input.Send = message => { var current = link; if (current != null) _ = current.Send(message); };
                input.Status = text => SetStatus(text);
                ConfigureInput();
                Start();
            } catch (Exception exception) {
                Diagnostics.Write("input-hooks-failed", exception: exception);
                SetStatus(exception.Message, true);
            }
        };
        FormClosing += (_, _) => { Stop(); input?.Dispose(); };
        LoadState();
        ResumeLayout(false);
    }

    static int AddressPriority(IPAddress address) {
        var bytes = address.GetAddressBytes();
        if (bytes[0] == 192 && bytes[1] == 168) return 0;
        if (bytes[0] == 10) return 1;
        if (bytes[0] == 172 && bytes[1] is >= 16 and <= 31) return 2;
        if (bytes[0] == 100 && bytes[1] is >= 64 and <= 127) return 3;
        return 4;
    }

    static BridgeDisplay[] EnumerateLocalDisplays() => Screen.AllScreens
        .Select((screen, index) => new BridgeDisplay(
            screen.DeviceName,
            $"Display {index + 1}",
            screen.Bounds.X,
            screen.Bounds.Y,
            screen.Bounds.Width,
            screen.Bounds.Height,
            screen.Primary))
        .OrderBy(display => display.X)
        .ThenBy(display => display.Y)
        .ToArray();

    static Side Opposite(Side side) => side switch {
        Side.right => Side.left,
        Side.left => Side.right,
        Side.above => Side.below,
        _ => Side.above
    };

    static string? DefaultDisplay(IReadOnlyList<BridgeDisplay> displays, Side exposedEdge) {
        var index = DisplayPortal.SelectExtremeIndex(displays.Select(display => display.Bounds).ToArray(), exposedEdge);
        return index < 0 ? null : displays[index].Id;
    }

    static BridgeDisplay[] ParseDisplays(JsonElement message) {
        if (!message.TryGetProperty("displays", out var value) || value.ValueKind != JsonValueKind.Array) return [];
        var displays = new List<BridgeDisplay>();
        foreach (var item in value.EnumerateArray().Take(16)) {
            try {
                var id = item.GetProperty("id").GetString()?.Trim();
                var name = item.TryGetProperty("name", out var nameValue) ? nameValue.GetString()?.Trim() : null;
                var x = item.GetProperty("x").GetInt32();
                var y = item.GetProperty("y").GetInt32();
                var width = item.GetProperty("width").GetInt32();
                var height = item.GetProperty("height").GetInt32();
                var primary = item.TryGetProperty("primary", out var primaryValue) && primaryValue.GetBoolean();
                if (string.IsNullOrWhiteSpace(id) || id.Length > 128 || width is < 1 or > 32768 || height is < 1 or > 32768) continue;
                displays.Add(new BridgeDisplay(id, string.IsNullOrWhiteSpace(name) ? id : name[..Math.Min(name.Length, 128)], x, y, width, height, primary));
            } catch { }
        }
        return displays.DistinctBy(display => display.Id, StringComparer.Ordinal).ToArray();
    }

    object DisplaysMessage() => new {
        type = "displays",
        displays = windowsDisplays.Select(display => new {
            id = display.Id,
            name = display.Name,
            x = display.X,
            y = display.Y,
            width = display.Width,
            height = display.Height,
            primary = display.Primary
        }).ToArray()
    };

    object LayoutMessage() => new {
        type = "layout",
        side = layout.Side.ToString(),
        macDisplay = layout.SelectedMacDisplay ?? string.Empty,
        windowsDisplay = layout.SelectedWindowsDisplay ?? string.Empty
    };

    async Task SendPeerState(Link session) {
        await session.Send(DisplaysMessage());
        if (link == session) await session.Send(LayoutMessage());
    }

    void ConfigureInput() => ConfigureInput(layout.Side, layout.SelectedWindowsDisplay);

    void ConfigureInput(Side side, string? selectedDisplay) {
        _ = ConfigureInputAsync(side, selectedDisplay);
    }

    Task ConfigureInputAsync(Side side, string? selectedDisplay) {
        if (input == null) return Task.CompletedTask;
        var selected = windowsDisplays.FirstOrDefault(display => display.Id == selectedDisplay)
            ?? windowsDisplays.FirstOrDefault(display => display.Id == DefaultDisplay(windowsDisplays, Opposite(side)));
        return selected != null
            ? input.ConfigureAsync(side, selected.Bounds, windowsDisplays.Select(display => display.Bounds))
            : Task.CompletedTask;
    }

    void LoadState() {
        try {
            var saved = File.ReadAllText(StateFile);
            if (!saved.TrimStart().StartsWith('{')) {
                if (Enum.TryParse<Side>(saved, out var legacySide)) SetBridgeLayout(legacySide, null, null, false, false, true);
                return;
            }
            using var document = JsonDocument.Parse(saved);
            var root = document.RootElement;
            var side = root.TryGetProperty("side", out var sideValue) && Enum.TryParse<Side>(sideValue.GetString(), out var parsedSide)
                ? parsedSide : Side.right;
            var macDisplay = root.TryGetProperty("macDisplay", out var macValue) ? macValue.GetString() : null;
            var windowsDisplay = root.TryGetProperty("windowsDisplay", out var windowsValue) ? windowsValue.GetString() : null;
            if (!windowsDisplays.Any(display => display.Id == windowsDisplay))
                windowsDisplay = DefaultDisplay(windowsDisplays, Opposite(side));
            SetBridgeLayout(side, macDisplay, windowsDisplay, false);
        } catch { }
    }

    static Label NewLabel(string text, float size, FontStyle style, Rectangle bounds, Color color, ContentAlignment alignment = ContentAlignment.MiddleLeft) => new() {
        Text = text,
        Bounds = bounds,
        Font = new Font("Segoe UI", size, style),
        ForeColor = color,
        BackColor = Color.Transparent,
        TextAlign = alignment,
        AutoEllipsis = true
    };

    void AddLabel(string text, float size, FontStyle style, Rectangle bounds, Color color, ContentAlignment alignment = ContentAlignment.MiddleLeft) =>
        Controls.Add(NewLabel(text, size, style, bounds, color, alignment));

    void SetStatus(string text, bool attention = false) {
        if (InvokeRequired) { UI(() => SetStatus(text, attention)); return; }
        var lower = text.ToLowerInvariant();
        var tone = attention || lower.Contains("could not") || lower.Contains("blocked") || lower.Contains("ended")
            ? Theme.Red
            : lower.StartsWith("connected") ? Theme.Green
            : listening || lower.Contains("listening") || lower.Contains("pairing code") ? Theme.Teal
            : Theme.Subtle;
        var pill = tone == Theme.Red ? "Attention" : lower.StartsWith("connected") ? "Connected" : listening ? "Listening" : "Paused";
        status.Set(text, tone);
        statusPill.Set(pill, tone);
        listen.Text = listening ? "Stop listening" : "Start listening";
        listen.Invalidate();
    }

    void RotatePairingCode() {
        pairingCode = PairingCode.Create();
        pairing.Value = pairingCode;
        Diagnostics.Write("pairing-code-rotated");
    }

    void RecordPairingFailure() {
        failedPairingAttempts++;
        Diagnostics.Write("pairing-proof-failed", $"attempt={failedPairingAttempts}");
        if (failedPairingAttempts < 5) {
            SetStatus($"Pairing failed · {5 - failedPairingAttempts} attempts remain before the code changes", true);
            return;
        }
        failedPairingAttempts = 0;
        cooldownUntilUtc = DateTime.UtcNow.AddSeconds(30);
        RotatePairingCode();
        SetStatus("Too many wrong codes · new code created, pairing paused for 30 seconds", true);
    }

    void QueueRemoteInput(Link session, JsonElement message) {
        try {
            var result = remoteInputBuffer.Enqueue(session, message, out var scheduleDrain);
            if (result == RemoteEnqueueResult.Queued) {
                if (scheduleDrain) _ = Task.Run(DrainRemoteInputs);
                return;
            }
        } catch (Exception exception) {
            Diagnostics.Write("queue-remote-input", exception: exception);
            session.Dispose();
            return;
        }
        Diagnostics.Write("remote-input-overflow", "limit=256");
        UI(() => {
            input?.ReturnLocal(false);
            SetStatus("Remote input queue overflow · control returned locally", true);
        });
        session.Dispose();
    }

    async Task DrainRemoteInputs() {
        await remoteInputSerial.WaitAsync().ConfigureAwait(false);
        try {
            while (remoteInputBuffer.TryDequeue(out var item, out _) && item != null) {
                if (link != item.Session) continue;
                try {
                    var message = item.IsMove
                        ? JsonSerializer.SerializeToElement(new { type = "move", dx = item.Dx, dy = item.Dy })
                        : item.Message;
                    var messageType = message.GetProperty("type").GetString();
                    if (messageType == "displays") {
                        var displays = ParseDisplays(message);
                        UI(() => SetMacDisplays(displays));
                    } else if (messageType == "layout" &&
                        Enum.TryParse<Side>(message.GetProperty("side").GetString(), out var side)) {
                        var macDisplay = message.TryGetProperty("macDisplay", out var macValue) ? macValue.GetString() : null;
                        var windowsDisplay = message.TryGetProperty("windowsDisplay", out var windowsValue) ? windowsValue.GetString() : null;
                        var effectiveWindowsDisplay = windowsDisplays.Any(display => display.Id == windowsDisplay)
                            ? windowsDisplay
                            : windowsDisplays.Any(display => display.Id == layout.SelectedWindowsDisplay)
                                ? layout.SelectedWindowsDisplay
                                : DefaultDisplay(windowsDisplays, Opposite(side));
                        await ConfigureInputAsync(side, effectiveWindowsDisplay).ConfigureAwait(false);
                        UI(() => SetBridgeLayout(side, macDisplay, effectiveWindowsDisplay, false, true));
                    } else if (input != null) await input.ReceiveAsync(message).ConfigureAwait(false);
                } catch (Exception exception) {
                    var type = item.IsMove ? "move" : item.Message.TryGetProperty("type", out var value) ? value.GetString() ?? "unknown" : "missing";
                    Diagnostics.Write("session-message-failed", $"type={type}", exception);
                    ClearRemoteInputs();
                    input?.ReturnLocal(false);
                    item.Session.Dispose();
                    break;
                }
            }
        } finally {
            remoteInputSerial.Release();
        }
    }

    void ClearRemoteInputs() => remoteInputBuffer.Clear();

    void SetMacDisplays(BridgeDisplay[] displays) {
        macDisplays = displays;
        layout.MacDisplays = displays;
        var selected = layout.SelectedMacDisplay;
        if (string.IsNullOrWhiteSpace(selected) || !displays.Any(display => display.Id == selected))
            selected = DefaultDisplay(displays, layout.Side);
        var changed = selected != layout.SelectedMacDisplay;
        layout.SelectedMacDisplay = selected;
        layout.Invalidate();
        if (changed && link != null) _ = link.Send(LayoutMessage());
    }

    void SetBridgeLayout(Side side, string? macDisplay, string? windowsDisplay, bool sync,
        bool inputAlreadyConfigured = false, bool resetDefaults = false) {
        var selectedWindows = !resetDefaults && windowsDisplays.Any(display => display.Id == windowsDisplay)
            ? windowsDisplay
            : !resetDefaults && windowsDisplays.Any(display => display.Id == layout.SelectedWindowsDisplay)
                ? layout.SelectedWindowsDisplay
                : DefaultDisplay(windowsDisplays, Opposite(side));
        var selectedMac = !resetDefaults && !string.IsNullOrWhiteSpace(macDisplay) &&
            (macDisplays.Length == 0 || macDisplays.Any(display => display.Id == macDisplay))
                ? macDisplay
                : !resetDefaults && (macDisplays.Length == 0 || macDisplays.Any(display => display.Id == layout.SelectedMacDisplay))
                    ? layout.SelectedMacDisplay
                    : DefaultDisplay(macDisplays, side);
        var changed = resetDefaults || layout.Side != side || layout.SelectedMacDisplay != selectedMac || layout.SelectedWindowsDisplay != selectedWindows;
        if (!inputAlreadyConfigured && changed && link != null) input?.ReturnLocal(sync);
        layout.Side = side;
        layout.SelectedMacDisplay = selectedMac;
        layout.SelectedWindowsDisplay = selectedWindows;
        layout.Invalidate();
        position.SelectedSide = side;
        if (!inputAlreadyConfigured) ConfigureInput(side, selectedWindows);
        try {
            Directory.CreateDirectory(Path.GetDirectoryName(StateFile)!);
            File.WriteAllText(StateFile, JsonSerializer.Serialize(new {
                side = side.ToString(),
                macDisplay = selectedMac ?? string.Empty,
                windowsDisplay = selectedWindows ?? string.Empty
            }));
        } catch { }
        if (sync && link != null) _ = link.Send(LayoutMessage());
    }

    void UI(Action action) {
        if (!IsDisposed && IsHandleCreated) {
            try { BeginInvoke(action); } catch { }
        }
    }

    void Start() {
        if (listening || input == null) return;
        try {
            listener = new TcpListener(IPAddress.Any, 24872);
            listener.Start(4);
            listening = true;
            Diagnostics.Write("listener-started", "port=24872");
            SetStatus("Listening on TCP 24872 · ready for your Mac");
            _ = Accept(listener);
        } catch (Exception exception) {
            listening = false;
            Diagnostics.Write("listener-failed", exception: exception);
            SetStatus("Could not listen: " + exception.Message, true);
        }
    }

    async Task Accept(TcpListener server) {
        while (listening && listener == server) {
            TcpClient client;
            try { client = await server.AcceptTcpClientAsync(); } catch { return; }
            var cooldownRemaining = cooldownUntilUtc - DateTime.UtcNow;
            if (cooldownRemaining > TimeSpan.Zero) {
                Diagnostics.Write("connection-rejected", "reason=cooldown");
                client.Close();
                SetStatus($"Pairing paused after wrong codes · try again in {Math.Ceiling(cooldownRemaining.TotalSeconds)} seconds", true);
                continue;
            }
            if (link != null) { client.Close(); continue; }
            Diagnostics.Write("connection-accepted");
            var session = new Link(client);
            ClearRemoteInputs();
            link = session;
            var codeForAttempt = pairingCode;
            var secretForAttempt = await Task.Run(() => PairingCode.Derive(codeForAttempt));
            session.AuthenticationFailed += () => UI(RecordPairingFailure);
            session.Ready += () => {
                input?.SetConnected(true);
                _ = SendPeerState(session);
                UI(() => {
                    if (link != session) return;
                    failedPairingAttempts = 0;
                    cooldownUntilUtc = DateTime.MinValue;
                    RotatePairingCode();
                    Diagnostics.Write("session-ready");
                    SetStatus("Connected · controlling this Windows PC");
                });
            };
            session.Message += message => QueueRemoteInput(session, message);
            session.Closed += text => {
                ClearRemoteInputs();
                input?.SetConnected(false);
                UI(() => {
                    if (link != session) return;
                    Diagnostics.Write("session-closed", text);
                    link = null;
                    var coolingDown = cooldownUntilUtc > DateTime.UtcNow;
                    if (coolingDown) SetStatus("Too many wrong codes · pairing paused for 30 seconds", true);
                    else if (text.Contains("Pairing failed", StringComparison.OrdinalIgnoreCase))
                        SetStatus($"Pairing failed · {5 - failedPairingAttempts} attempts remain before the code changes", true);
                    else SetStatus(text + " · waiting for reconnect", text.Contains("ended", StringComparison.OrdinalIgnoreCase));
                });
            };
            _ = RunSession(session, secretForAttempt);
        }
    }

    static async Task RunSession(Link session, byte[] secret) {
        try { await Task.Run(() => session.Run(secret)).ConfigureAwait(false); }
        finally { CryptographicOperations.ZeroMemory(secret); }
    }

    void Stop() {
        listening = false;
        listener?.Stop();
        listener = null;
        link?.Dispose();
        link = null;
        input?.SetConnected(false);
        Diagnostics.Write("listener-stopped");
        SetStatus("Not listening");
    }

}

static class Program {
    [STAThread]
    static void Main() {
        Application.SetUnhandledExceptionMode(UnhandledExceptionMode.CatchException);
        Application.ThreadException += (_, args) => Diagnostics.Write("ui-thread-unhandled", exception: args.Exception);
        AppDomain.CurrentDomain.UnhandledException += (_, args) => Diagnostics.Write(
            "app-domain-unhandled",
            $"terminating={args.IsTerminating}",
            args.ExceptionObject as Exception);
        TaskScheduler.UnobservedTaskException += (_, args) => {
            Diagnostics.Write("task-unobserved", exception: args.Exception);
            args.SetObserved();
        };
        Diagnostics.Write("app-start", $"version={typeof(Program).Assembly.GetName().Version}");
        ApplicationConfiguration.Initialize();
        Application.Run(new MainForm());
        Diagnostics.Write("app-exit");
    }
}
