const std = @import("std");

const suharyk = @import("suharyk");
const entities = suharyk.entities;
const Device = entities.Device;
const ServerPayload = suharyk.packet.ServerPayload;
const ClientPayload = suharyk.packet.ClientPayload;

const Player = @import("./game/Player.zig");
const VBoard = @import("./game/VBoard.zig");
const SyncCircularQueue = @import("./SyncCircularQueue.zig");
const Duplex = @import("Duplex.zig");

const Tickable = @import("./game/Tickable.zig");
const Game = @This();
const ClientRequest = struct {
    player: *Player,
    pl: *ClientPayload,
};

var gpa: std.heap.DebugAllocator(.{}) = .init;
pub const allocator = gpa.allocator();

const seed: u64 = undefined;
pub var prng = std.Random.Pcg.init(seed).random();

var players: std.ArrayListUnmanaged(*Player) = .empty;
var game_thread: ?std.Thread = null;
// Flyweight pattern
pub var name_list: std.ArrayListUnmanaged([]u8) = .empty;
var cmd_queue: SyncCircularQueue.of(ClientRequest, 512) = .{};
var vboard: VBoard = undefined;
pub var on_tick: std.ArrayListUnmanaged(Tickable) = .empty;

pub fn addPlayer(player: *Player) !void {
    try players.append(allocator, player);
    try name_list.append(allocator, player.name);
    std.log.info(
        "{s} joined the game",
        .{player.name},
    );

    const joined_msg: ServerPayload = .{
        .BroadcastJoin = .{
            .name = player.name,
        },
    };
    broadcast(player.id, joined_msg);
}

pub fn playerDuplexLoop(player: *Player) !void {
    defer {
        _ = players.swapRemove(player.id);
        players.items[player.id].id = player.id;
        const left_msg: ServerPayload = .{
            .BroadcastLeave = .{
                .name = player.name,
            },
        };
        broadcast(player.id, left_msg);
        std.log.info(
            "{s} left the game",
            .{player.name},
        );
    }
    while (!player.disconnect) {
        // TODO: handle client actions
        var pl: suharyk.packet.ClientPayload = undefined;
        try player.duplex.recieve(&pl);
        defer player.duplex.freePacket(pl);
    }
}

fn broadcast(player_id: usize, info: anytype) void {
    for (players.items) |player| {
        if (player.id != player_id) {
            player.duplex.send(info) catch |e| {
                // Possibly, connection is closed from other thread
                std.log.debug("Failed to broadcast: {any}", .{e});
                std.log.debug("{any}", .{@errorReturnTrace()});
            };
        }
    }
}

pub inline fn playerCount() usize {
    return players.items.len;
}

pub inline fn getPlayers() @TypeOf(players) {
    return players;
}

pub inline fn gameStarted() bool {
    return game_thread != null;
}

fn start() void {
    std.log.info("Game started", .{});
    vboard.generate();
}
