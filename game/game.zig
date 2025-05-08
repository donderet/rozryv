const std = @import("std");

const GameState = @import("GameState.zig");
const suharyk = @import("suharyk");
const ServerPayload = suharyk.packet.ServerPayload;
const ClientPayload = suharyk.packet.ClientPayload;
const SyncCircularQueue = suharyk.SyncCircularQueue;
const Duplex = @import("Duplex.zig");
const Settings = @import("Settings.zig");
var gpa: std.heap.DebugAllocator(.{}) = .init;
pub const allocator = gpa.allocator();
// State pattern
var state: GameState = @import("MenuGameState.zig").init();
var serv_proc: ?std.process.Child = null;
pub var duplex: Duplex = undefined;

pub var spl_queue: SyncCircularQueue.of(ServerPayload, 64) = .{};
pub var cpl_queue: SyncCircularQueue.of(ClientPayload, 64) = .{};

pub var settings: Settings = .{};
pub var is_host = false;
var money_amount = 0;

pub fn getState() GameState {
    return state;
}

pub fn init() !void {
    // TODO: load settings
}

pub fn changeState(new_state: GameState) void {
    state.deinit();
    state = new_state;
}

pub fn startServer() !void {
    is_host = true;
    var sexe_buf: [256]u8 = undefined;
    const sexe = try std.fs.cwd().realpath(
        @import("server_options").exe_name,
        &sexe_buf,
    );

    serv_proc = std.process.Child.init(
        &[_][]const u8{sexe},
        allocator,
    );
    if (@import("builtin").mode != .Debug) {
        serv_proc.?.stdout_behavior = .Ignore;
        serv_proc.?.stderr_behavior = .Ignore;
    }
    try serv_proc.?.spawn();
    serv_proc.?.waitForSpawn() catch |e| {
        std.log.debug("Failed to spawn server: {any}", .{e});
        return e;
    };
}

pub fn stopServer() void {
    is_host = false;
    if (serv_proc) |*proc| _ = proc.kill() catch {};
    serv_proc = null;
}

pub fn join(addr: std.net.Address) !void {
    const stream = try std.net.tcpConnectToAddress(addr);
    suharyk.net.setKeepalive(stream.handle) catch |e| {
        std.log.debug("Can't set keepalive: {any}", .{e});
        std.log.debug("{any}", .{@errorReturnTrace()});
        return;
    };
    errdefer stream.close();
    var raw_duplex: suharyk.Duplex = .init(stream, allocator);
    const hello: suharyk.client_hello = .{
        .name = settings.player_name,
        .prot_ver = suharyk.version,
    };
    try raw_duplex.send(hello);
    duplex = .init(raw_duplex);
}

pub fn disconnect() void {
    duplex.send(.{
        .Leave = {},
    }) catch {
        std.log.debug("Can't send leave packet. Server closed?", .{});
    };
    duplex.suharyk_duplex.deinit();
    spl_queue.mut.lock();
    spl_queue = .{};
    spl_queue.mut.unlock();
    cpl_queue.mut.lock();
    cpl_queue = .{};
    cpl_queue.mut.unlock();
}

pub fn startDuplexLoop() !void {
    {
        const t = try std.Thread.spawn(.{}, duplexSendLoop, .{});
        t.detach();
    }
    {
        const t = try std.Thread.spawn(.{}, duplexRecieveLoop, .{});
        t.detach();
    }
}

pub fn duplexSendLoop() void {
    loop: while (true) {
        while (cpl_queue.dequeue()) |req| {
            std.log.debug("Sending request to server: {any}", .{req});
            duplex.send(req) catch |e| switch (e) {
                error.ConnectionResetByPeer,
                error.BrokenPipe,
                => break :loop,
                else => {
                    std.log.debug("Unexpected err: {any}", .{e});
                },
            };
            if (req == .Leave) break :loop;
        }
        std.Thread.sleep(std.time.ns_per_ms);
    }
}

pub fn duplexRecieveLoop() void {
    loop: while (true) {
        if (!(state.is(
            @import("HackGameState.zig"),
        ) or state.is(
            @import("WaitGameState.zig"),
        ))) break;
        // var b: [128]u8 = undefined;
        // const size = duplex.suharyk_duplex.br.read(&b) catch |e| {
        //     std.log.debug("Err: {any}", .{e});
        //     continue;
        // };
        // std.log.debug("Recieved bytes: {d}", .{b[0..size]});
        // if (true) {
        //     std.Thread.sleep(std.time.ns_per_s);
        //     continue;
        // }
        var pl: suharyk.packet.ServerPayload = undefined;
        duplex.recieve(&pl) catch |e| switch (e) {
            error.NoUpdates => {
                std.Thread.sleep(std.time.ns_per_ms);
                continue :loop;
            },
            error.ConnectionResetByPeer,
            error.ConnectionTimedOut,
            error.Canceled,
            error.EndOfStream,
            error.BrokenPipe,
            error.NotOpenForReading,
            => break :loop,
            else => {
                std.log.debug("Unexpected err: {any}", .{e});
            },
        };
        spl_queue.enqueueWait(pl);
        if (pl == .Error or pl == .GameOver or pl == .Victory) {
            break;
        }
    }
    std.log.debug("Shutting down duplex", .{});
    duplex.suharyk_duplex.deinit();
}
