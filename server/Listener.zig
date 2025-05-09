const std = @import("std");

const suharyk = @import("suharyk");

const Player = @import("./game/Player.zig");
const Duplex = @import("Duplex.zig");
const Game = @import("Game.zig");

var wgroup: std.Thread.WaitGroup = .{};
var pool: std.Thread.Pool = undefined;

var server: std.net.Server = undefined;

pub fn start(
    addr: std.net.Address,
    allocator: std.mem.Allocator,
) !void {
    server = try addr.listen(.{
        .reuse_port = true,
    });
    try pool.init(.{
        .allocator = allocator,
        .n_jobs = 2,
    });
    defer {
        server.deinit();
        pool.deinit();
    }

    std.log.info("Starting listening on {d}", .{addr.getPort()});

    while (true) {
        const con = try server.accept();
        suharyk.net.setKeepalive(con.stream.handle) catch |e| {
            std.log.debug("Can't set keepalive: {any}", .{e});
            std.log.debug("{any}", .{@errorReturnTrace()});
            continue;
        };
        pool.spawnWg(
            &wgroup,
            struct {
                fn run(
                    connection: std.net.Server.Connection,
                    a: std.mem.Allocator,
                ) void {
                    connectNewClient(connection, a) catch |e| {
                        std.log.err("Error while handling connection: {any}", .{e});
                        std.log.debug("{any}", .{@errorReturnTrace()});
                    };
                }
            }.run,
            .{ con, allocator },
        );
    }
}

fn connectNewClient(
    connection: std.net.Server.Connection,
    a: std.mem.Allocator,
) !void {
    var suharyk_duplex = suharyk.Duplex.init(
        connection.stream,
        a,
    );
    var duplex = Duplex.init(suharyk_duplex);

    var join_req: suharyk.client_hello = undefined;
    suharyk_duplex.recieve(&join_req) catch {
        std.log.debug(
            "Client closed connection without join request",
            .{},
        );
        return;
    };
    const accept_join = !Game.gameStarted() and join_req.prot_ver == suharyk.version;
    const resp: suharyk.server_hello = .{
        .ok = accept_join,
        .members = if (accept_join) Game.name_list.items else null,
    };
    try suharyk_duplex.send(resp);
    if (!resp.ok) {
        std.log.info(
            "Protocol version mismatched for player {s}",
            .{join_req.name},
        );
        return;
    }
    var player = try Player.init(
        a,
        Game.playerCount(),
        join_req.name,
        &duplex,
    );
    defer player.deinit();
    try Game.addPlayer(&player);
    suharyk_duplex.freePacket(join_req);
    const t = try std.Thread.spawn(.{}, Player.duplexRecieveLoop, .{&player});
    t.detach();
    try player.duplexSendLoop();
}
