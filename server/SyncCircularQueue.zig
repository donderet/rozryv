const std = @import("std");

const len_t = u16;

pub fn of(comptime T: type, queue_max_size: len_t) type {
    return struct {
        const SyncCircularQueue = @This();

        mut: std.Thread.Mutex = .{},
        arr: [queue_max_size]?T = .{null} ** queue_max_size,
        first_i: len_t = 0,
        last_i: len_t = 0,

        pub fn enqueueWait(queue: *SyncCircularQueue, pl: T) void {
            queue.mut.lock();
            defer queue.mut.unlock();
            var i = queue.getNextLastIndex();
            const wait = queue.arr[i] != null;
            if (wait) {
                queue.mut.unlock();
                std.log.warn("queue: Waiting for free space...", .{});
            }
            while (queue.arr[i] != null) {}
            if (wait) {
                queue.mut.lock();
                std.log.warn("queue: Done waiting!", .{});
                i = queue.getNextLastIndex();
            }
            queue.arr[i] = pl;
            queue.last_i = i;
        }

        pub inline fn hasMore(queue: SyncCircularQueue) bool {
            return queue.last_i != queue.first_i and queue.arr[queue.first_i] == null;
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
            queue.mut.lock();
            defer queue.mut.unlock();
            const i = queue.getNextIndex();
            defer queue.first_i = i;
            defer queue.arr[i] = null;
            return queue.arr[i];
        }
    };
}

test "endequeue" {
    std.testing.log_level = .debug;
    var queue: of(u16, 4) = .{};
    try std.testing.expect(queue.hasMore() == false);
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
                    if (q.hasMore()) {
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
