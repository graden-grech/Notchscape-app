using System.Text.Json;

namespace ScreenBridge;

enum RemoteEnqueueResult { Queued, Overflow }

sealed class QueuedRemoteInput<TSession>(TSession session, JsonElement message, bool isMove, double dx = 0, double dy = 0) where TSession : class {
    public TSession Session { get; } = session;
    public JsonElement Message { get; } = message;
    public bool IsMove { get; } = isMove;
    public double Dx { get; set; } = dx;
    public double Dy { get; set; } = dy;
}

sealed class RemoteInputBuffer<TSession>(int maximumPending = 256) where TSession : class {
    readonly object gate = new();
    readonly Queue<QueuedRemoteInput<TSession>> queue = new();
    QueuedRemoteInput<TSession>? coalescedMove;
    bool drainScheduled;

    public int Count { get { lock (gate) return queue.Count; } }

    public RemoteEnqueueResult Enqueue(TSession session, JsonElement message, out bool scheduleDrain) {
        lock (gate) {
            var type = message.GetProperty("type").GetString();
            if (type == "move") {
                var dx = message.GetProperty("dx").GetDouble();
                var dy = message.GetProperty("dy").GetDouble();
                var combinedX = (coalescedMove?.Dx ?? 0) + dx;
                var combinedY = (coalescedMove?.Dy ?? 0) + dy;
                if (coalescedMove != null && coalescedMove.Session == session && Math.Abs(combinedX) <= 4096 && Math.Abs(combinedY) <= 4096) {
                    coalescedMove.Dx = combinedX;
                    coalescedMove.Dy = combinedY;
                } else {
                    coalescedMove = new QueuedRemoteInput<TSession>(session, default, true, dx, dy);
                    queue.Enqueue(coalescedMove);
                }
            } else {
                // A non-move event is an ordering barrier. Later moves must form a new segment.
                coalescedMove = null;
                queue.Enqueue(new QueuedRemoteInput<TSession>(session, message, false));
            }

            if (queue.Count > maximumPending) {
                queue.Clear();
                coalescedMove = null;
                drainScheduled = false;
                scheduleDrain = false;
                return RemoteEnqueueResult.Overflow;
            }

            scheduleDrain = !drainScheduled;
            if (scheduleDrain) drainScheduled = true;
            return RemoteEnqueueResult.Queued;
        }
    }

    public bool TryDequeue(out QueuedRemoteInput<TSession>? item, out bool scheduleNext) {
        lock (gate) {
            if (queue.Count == 0) {
                item = null;
                scheduleNext = false;
                drainScheduled = false;
                return false;
            }
            item = queue.Dequeue();
            if (ReferenceEquals(item, coalescedMove)) coalescedMove = null;
            scheduleNext = queue.Count > 0;
            if (!scheduleNext) drainScheduled = false;
            return true;
        }
    }

    public void Clear() {
        lock (gate) {
            queue.Clear();
            coalescedMove = null;
            drainScheduled = false;
        }
    }
}
