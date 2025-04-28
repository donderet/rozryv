const std = @import("std");

const suharyk = @import("suharyk");
const ServerPayload = suharyk.packet.ServerPayload;
const ClientPayload = suharyk.packet.ClientPayload;

const Duplex = @import("../Duplex.zig");
const Game = @import("../Game.zig");
const SyncCircularQueue = @import("../SyncCircularQueue.zig");
const Device = @import("Device.zig");

const Player = @This();

allocator: std.mem.Allocator,
duplex: *Duplex,
server_req_queue: SyncCircularQueue.of(ServerPayload, 128) = .{},
id: usize,
disconnect: bool = false,

is_host: bool = false,
name: []u8,
money_amount: usize = 0,
device: *Device = undefined,

pub fn init(
    allocator: std.mem.Allocator,
    id: usize,
    name: []const u8,
    duplex: *Duplex,
) !Player {
    const p: Player = .{
        .allocator = allocator,
        .id = id,
        .duplex = duplex,
        .name = try allocator.dupe(u8, name),
        .is_host = Game.name_list.items.len == 0,
    };
    return p;
}

pub fn startGame(player: *Player) !void {
    if (Game.game_thread != null) {
        player.duplex.sendPacket(.{
            .Error = .GameAlreadyStarted,
        });
        return;
    }
    if (!player.is_host) {
        player.duplex.send(.{
            .Error = .IllegalSuharyk,
        });
        return;
    }
    Game.game_thread = std.Thread.spawn(
        .{},
        Game.start,
        .{},
    );
}

pub fn deinit(player: *Player) void {
    _ = Game.name_list.swapRemove(player.id);
    player.allocator.free(player.name);
}

pub fn duplexLoop(player: *Player) !void {
    var players = &Game.players;
    defer {
        _ = players.swapRemove(player.id);
        if (player.id != players.items.len)
            players.items[player.id].id = player.id;
        const left_msg: ServerPayload = .{
            .BroadcastLeave = .{
                .name = player.name,
            },
        };
        Game.broadcast(player.id, left_msg);
        std.log.info(
            "{s} left the game",
            .{player.name},
        );
    }
    loop: while (!player.disconnect) {
        while (player.server_req_queue.dequeue()) |req| {
            player.duplex.send(req);
        }
        var pl: suharyk.packet.ClientPayload = undefined;
        player.duplex.recieve(&pl) catch |e| switch (e) {
            error.NoUpdates => {
                std.Thread.sleep(1_000_000);
                continue :loop;
            },
            error.ConnectionResetByPeer,
            error.ConnectionTimedOut,
            error.Canceled,
            error.EndOfStream,
            error.BrokenPipe,
            error.NotOpenForReading,
            => break :loop,
            else => return e,
        };
        if (pl == .Leave) {
            std.log.debug("Got Leave packet", .{});
            break;
        }

        defer player.duplex.freePacket(pl);
    }
}
