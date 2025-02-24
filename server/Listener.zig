const std = @import("std");
const ClientHanler = @import("./ClientHandler.zig");

const listener_thread: std.Thread = undefined;
var wgroup: std.Thread.WaitGroup = .{};
var pool: std.Thread.Pool = undefined;

var server: std.net.Server = undefined;

pub var clients: std.ArrayList(ClientHanler) = undefined;

pub fn start(
    addr: std.net.Address,
    allocator: std.mem.Allocator,
) !void {
    clients = std.ArrayList(ClientHanler).init(allocator);
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

        var handler = ClientHanler.init(con, allocator);
        clients.append(handler) catch |e| {
            std.log.err("Can't append new client: {}", .{e});
        };
        defer disconnect(handler);
        try handler.handle();
        //
        // pool.spawnWg(&wgroup, struct {
        //     fn run(
        //         connection: std.net.Server.Connection,
        //         a: std.mem.Allocator,
        //     ) void {
        //         var handler = ClientHanler.init(connection, a);
        //         clients.append(handler) catch |e| {
        //             std.log.err("Can't append new client: {}", .{e});
        //         };
        //         defer disconnect(handler);
        //         handler.handle() catch |e| {
        //             std.log.err("Couldn't handle connection: {}", .{e});
        //         };
        //     }
        // }.run, .{ con, allocator });
    }
}

fn disconnect(handler: ClientHanler) void {
    _ = clients.swapRemove(handler.id);
    if (clients.items.len != 0) {
        clients.items[handler.id].id = handler.id;
    }
    std.log.debug("Closed connection for {}", .{handler.connection.address});
}
