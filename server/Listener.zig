const std = @import("std");
const Client = @import("./Client.zig");

const listener_thread: std.Thread = undefined;
var wgroup: std.Thread.WaitGroup = .{};
var pool: std.Thread.Pool = undefined;

var server: std.net.Server = undefined;

pub var clients: std.ArrayList(Client) = undefined;

pub fn start(
    addr: std.net.Address,
    allocator: std.mem.Allocator,
) !void {
    clients = std.ArrayList(Client).init(allocator);
    defer clients.deinit();
    server = try addr.listen(.{});
    defer server.deinit();

    std.log.info("Starting listening on {d}", .{addr.getPort()});

    try pool.init(.{
        .allocator = allocator,
        .n_jobs = 2,
    });
    defer pool.deinit();
    try listen(allocator);
}

fn listen(allocator: std.mem.Allocator) !void {
    while (true) {
        const con = try server.accept();

        pool.spawnWg(&wgroup, struct {
            fn run(
                connection: std.net.Server.Connection,
                a: std.mem.Allocator,
            ) void {
                var client = Client.init(connection, a);
                clients.append(client) catch |e| {
                    std.log.err("Can't append new client: {}", .{e});
                };
                defer disconnect(client);
                client.handle() catch |e| {
                    std.log.err("Couldn't handle connection: {}", .{e});
                };
            }
        }.run, .{ con, allocator });
    }
}

fn disconnect(client: Client) void {
    _ = clients.swapRemove(client.id);
    if (client.id != clients.items.len and clients.items.len != 0) {
        clients.items[client.id].id = client.id;
    }
    std.log.debug("Closed connection for {}", .{client.connection.address});
}
