const std = @import("std");

const len_t = u16;

pub fn of(comptime T: type, queue_max_size: len_t) type {
    return struct {
        const SyncCircularQueue = @This();

        mut: std.Thread.Mutex = .{},
        arr: [queue_max_size]T = undefined,
        first_i: len_t = 0,
        last_i: len_t = 0,

        pub fn enqueueWait(queue: *SyncCircularQueue, pl: T) void {
            defer queue.mut.unlock();
            while (true) {
                if (queue.isFull()) {
                    queue.mut.unlock();
                    std.log.warn("queue: Waiting for free space...", .{});
                }
                while (queue.isFull()) {}
                queue.mut.lock();
                // Check once more while mutex is locked
                if (queue.isFull()) {
                    queue.mut.unlock();
                    continue;
                }
                const i = queue.getNextLastIndex();
                queue.arr[i] = pl;
                queue.last_i = i;
                break;
            }
        }

        pub inline fn isFull(queue: SyncCircularQueue) bool {
            return queue.len() == queue_max_size;
        }

        pub inline fn clear(queue: *SyncCircularQueue) void {
            queue.first_i = queue.last_i;
        }

        pub inline fn len(queue: SyncCircularQueue) len_t {
            return (queue_max_size + queue.last_i - queue.first_i) % queue_max_size;
        }

        pub inline fn getNextLastIndex(queue: SyncCircularQueue) len_t {
            return (queue.last_i + 1) % queue_max_size;
        }

        pub inline fn getNextIndex(queue: SyncCircularQueue) len_t {
            return (queue.first_i + 1) % queue_max_size;
        }

        pub fn dequeue(queue: *SyncCircularQueue) ?T {
            if (queue.len() == 0) return null;
            queue.mut.lock();
            defer queue.mut.unlock();
            const i = queue.getNextIndex();
            defer queue.first_i = i;
            return queue.arr[i];
        }
    };
}

test "endequeue" {
    std.testing.log_level = .debug;
    var queue: of(u16, 4) = .{};
    try std.testing.expect(queue.len() == 0);
    try std.testing.expect(queue.isFull() == false);
    queue.enqueueWait(32);
    queue.enqueueWait(1337);
    queue.enqueueWait(104);
    try std.testing.expect(queue.dequeue() == 32);
    try std.testing.expect(queue.dequeue() == 1337);
    try std.testing.expect(queue.dequeue() == 104);
    try std.testing.expect(queue.dequeue() == null);
}

test "sync endequeue" {
    std.testing.log_level = .debug;
    var queue: of(u16, 4) = .{};
    var pass = true;
    const threads_n = 20;
    const expected_sum = threads_n * (threads_n - 1) / 2;
    const consumer_thread = try std.Thread.spawn(
        .{},
        struct {
            fn run(q: *@TypeOf(queue), res: *bool) void {
                var el_left: u16 = threads_n;
                var sum: u16 = 0;
                while (el_left != 0) {
                    if (q.len() != 0) {
                        defer el_left -= 1;
                        const maybe_el = q.dequeue();
                        if (maybe_el) |el| {
                            sum += el;
                        } else {
                            std.log.err("Element is null: i: {d}, li: {d}", .{
                                q.first_i,
                                q.last_i,
                            });
                            _ = maybe_el.?;
                        }
                    }
                }
                std.testing.expect(expected_sum == sum) catch {
                    res.* = false;
                    std.log.err("Actual sum: {d}", .{sum});
                };
            }
        }.run,
        .{ &queue, &pass },
    );
    for (0..threads_n) |i| {
        _ = try std.Thread.spawn(
            .{},
            @TypeOf(queue).enqueueWait,
            .{
                &queue, @as(u16, @truncate(i)),
            },
        );
    }
    consumer_thread.join();
    try std.testing.expect(pass);
}
