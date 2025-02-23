const std = @import("std");
const ClientHanler = @import("./ClientHandler.zig");

const MAX_PLAYERS_COUNT = 4;
var wgroup: std.Thread.WaitGroup = .{};
const pool: std.Thread.Pool = undefined;
var server: std.net.Server = undefined;

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();

    const addr = std.net.Address.initIp4(.{ 127, 0, 0, 1 }, 6789);
    server = try addr.listen(.{});

    std.log.info("Starting listening on {d}", .{addr.getPort()});

    pool.init(.{
        .allocator = allocator,
        .n_jobs = MAX_PLAYERS_COUNT,
    });
    defer pool.deinit();

    addHandler(allocator);
}

fn addHandler(allocator: std.mem.Allocator) void {
    pool.spawnWg(&wgroup, struct {
        fn run(s: std.net.Server, a: std.mem.Allocator) void {
            const handler = ClientHanler.init(s, a);
            handler.on_connection_observers.append(struct {
                fn run(h: ClientHanler) void {
                    addHandler(h.allocator);
                }
            }.run);
            handler.handle();
        }
    }.run, .{ server, allocator });
}
