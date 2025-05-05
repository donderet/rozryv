const std = @import("std");

const suharyk = @import("suharyk");

const Duplex = @import("Duplex.zig");
const Game = @import("Game.zig");
const Player = @import("./game/Player.zig");

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
        setKeepalive(con.stream.handle) catch |e| {
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

fn setKeepalive(handle: std.posix.socket_t) !void {
    try std.posix.setsockopt(
        handle,
        std.posix.SOL.SOCKET,
        std.posix.SO.KEEPALIVE,
        &std.mem.toBytes(@as(c_int, 1)),
    );
    const idle_sec = 5;
    const intvl_sec = 1;
    if (@import("builtin").os.tag == .windows) {
        var keepalive_vals: std.os.windows.mst = extern struct {
            onoff: u32 = 1,
            keepalivetime: u32 = idle_sec * 1000,
            keepaliveinterval: u32 = intvl_sec * 1000,
        };

        const SIO_KEEPALIVE_VALS: u32 = 2550136836;

        const bytes_returned: std.os.windows.DWORD = undefined;
        const result = std.os.windows.WSAIoctl(
            handle,
            SIO_KEEPALIVE_VALS,
            @ptrCast(&keepalive_vals),
            @sizeOf(keepalive_vals),
            null,
            0,
            &bytes_returned,
            null,
            null,
        );
        if (result != 0) {
            const e = std.os.windows.ws2_32.WSAGetLastError();
            std.log.err(
                "Failed to set keepalive options with error {d}",
                .{e},
            );
            return error.WSAIoctlErr;
        }
    } else {
        try std.posix.setsockopt(
            handle,
            std.posix.IPPROTO.TCP,
            std.posix.TCP.KEEPIDLE,
            &std.mem.toBytes(@as(c_int, idle_sec)),
        );
        try std.posix.setsockopt(
            handle,
            std.posix.IPPROTO.TCP,
            std.posix.TCP.KEEPINTVL,
            &std.mem.toBytes(@as(c_int, intvl_sec)),
        );
        try std.posix.setsockopt(
            handle,
            std.posix.IPPROTO.TCP,
            std.posix.TCP.KEEPCNT,
            &std.mem.toBytes(@as(c_int, 3)),
        );
    }
}

fn connectNewClient(
    connection: std.net.Server.Connection,
    a: std.mem.Allocator,
) !void {
    var suharyk_duplex = suharyk.Duplex.init(
        connection,
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
    const accept_join = !Game.gameStarted() and join_req.prot_ver == suharyk.VERSION;
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
    try player.duplexLoop();
}
