using System.Text.Json;
using ScreenBridge;

static JsonElement Message(object value) => JsonSerializer.SerializeToElement(value);
static void Require(bool condition, string message) {
    if (!condition) throw new InvalidOperationException(message);
}

var session = new object();
var buffer = new RemoteInputBuffer<object>();
for (var index = 0; index < 1000; index++) {
    var result = buffer.Enqueue(session, Message(new { type = "move", dx = 1, dy = 0 }), out var schedule);
    Require(result == RemoteEnqueueResult.Queued, "Move burst overflowed unexpectedly");
    Require(schedule == (index == 0), "Drain scheduling was duplicated during a move burst");
}
Require(buffer.Count == 1, "Consecutive move burst was not coalesced");

buffer.Enqueue(session, Message(new { type = "button", button = 0, down = true }), out _);
buffer.Enqueue(session, Message(new { type = "button", button = 0, down = false }), out _);
for (var index = 0; index < 500; index++)
    buffer.Enqueue(session, Message(new { type = "move", dx = .5, dy = -.25 }), out _);
buffer.Enqueue(session, Message(new { type = "button", button = 1, down = true }), out _);
buffer.Enqueue(session, Message(new { type = "button", button = 1, down = false }), out _);
buffer.Enqueue(session, Message(new { type = "scroll", dx = 0, dy = 120 }), out _);
buffer.Enqueue(session, Message(new { type = "release" }), out _);
buffer.Enqueue(session, Message(new { type = "layout", side = "right" }), out _);

var order = new List<string>();
var moves = new List<(double X, double Y)>();
while (buffer.TryDequeue(out var item, out var scheduleNext)) {
    Require(item != null, "Dequeued item was null");
    var current = item!;
    if (current.IsMove) {
        order.Add("move");
        moves.Add((current.Dx, current.Dy));
    } else order.Add(current.Message.GetProperty("type").GetString() ?? "missing");
    Require(scheduleNext == (buffer.Count > 0), "Next-drain scheduling did not match queue state");
}
var expected = new[] { "move", "button", "button", "move", "button", "button", "scroll", "release", "layout" };
Require(order.SequenceEqual(expected), "Move/button/scroll/release/layout ordering changed");
Require(moves.Count == 2 && moves[0] == (1000, 0) && moves[1] == (250, -125), "Coalesced move totals changed");

var barrier = new RemoteInputBuffer<object>();
barrier.Enqueue(session, Message(new { type = "move", dx = 1, dy = 1 }), out _);
barrier.Enqueue(session, Message(new { type = "button", button = 0, down = true }), out _);
barrier.Enqueue(session, Message(new { type = "move", dx = 2, dy = 2 }), out _);
Require(barrier.Count == 3, "Non-move event did not split move segments");

var bounded = new RemoteInputBuffer<object>(256);
RemoteEnqueueResult overflowResult = RemoteEnqueueResult.Queued;
for (var index = 0; index < 257; index++)
    overflowResult = bounded.Enqueue(session, Message(new { type = "key", key = 65, down = index % 2 == 0 }), out _);
Require(overflowResult == RemoteEnqueueResult.Overflow, "Queue did not fail closed at 257 pending items");
Require(bounded.Count == 0, "Overflow did not clear pending input");

var leftDisplay = new Rectangle(-1920, 0, 1920, 1080);
var rightDisplay = new Rectangle(0, 0, 1920, 1080);
var localDisplays = new[] { leftDisplay, rightDisplay };
Require(DisplayPortal.SelectExtremeIndex(localDisplays, Side.left) == 0,
    "Windows-right layout did not default to the leftmost exposed Windows display");
Require(DisplayPortal.SelectExtremeIndex(localDisplays, Side.right) == 1,
    "Windows-left layout did not default to the rightmost exposed Windows display");
var verticalDisplays = new[] { new Rectangle(0, -1080, 1920, 1080), new Rectangle(0, 0, 1920, 1080) };
Require(DisplayPortal.SelectExtremeIndex(verticalDisplays, Side.above) == 0,
    "Below layout did not default to the topmost exposed display");
Require(DisplayPortal.SelectExtremeIndex(verticalDisplays, Side.below) == 1,
    "Above layout did not default to the bottommost exposed display");
Require(!DisplayPortal.CanCross(new Point(-1, 500), leftDisplay, localDisplays, Side.right, 4, 0),
    "Portal crossed an edge occupied by another local Windows display");
Require(DisplayPortal.CanCross(new Point(-1920, 500), leftDisplay, localDisplays, Side.left, -4, 0),
    "Portal rejected the selected display's exposed outer edge");
Require(!DisplayPortal.CanCross(new Point(0, 500), rightDisplay, localDisplays, Side.left, -4, 0),
    "Portal crossed from the primary display into the adjacent local display");
Require(DisplayPortal.CanCross(new Point(1919, 500), rightDisplay, localDisplays, Side.right, 4, 0),
    "Portal rejected the primary display's exposed outer edge");
Require(DisplayPortal.CanCross(new Point(1925, 500), rightDisplay, localDisplays, Side.right, 10, 0),
    "Portal rejected a next remote delta that crossed the selected display edge");
Require(!DisplayPortal.CanCross(new Point(1919, 1200), rightDisplay, localDisplays, Side.right, 4, 0),
    "Portal accepted a point outside the selected display's edge span");
Require(!DisplayPortal.CanStartCross(new Point(1925, 500), rightDisplay, localDisplays, Side.right, 10, 0),
    "Source capture started when the physical pointer was outside the selected monitor");

var inputService = new InputBridge();
var disconnectedStatusEvents = 0;
inputService.Status = _ => Interlocked.Increment(ref disconnectedStatusEvents);
await inputService.ReceiveAsync(Message(new { type = "enter", position = .5 }));
Require(disconnectedStatusEvents == 0, "Disconnected input service processed a late remote command");
await inputService.ConfigureAsync(Side.left, leftDisplay, localDisplays);
await inputService.ConfigureAsync(Side.right, rightDisplay, localDisplays);
inputService.Dispose();

Console.WriteLine("REMOTE_INPUT_BUFFER_TESTS_OK");
