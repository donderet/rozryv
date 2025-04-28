const std = @import("std");

const suharyk = @import("suharyk");
const entities = suharyk.entities;
const Device = entities.Device;
const ServerPayload = suharyk.packet.ServerPayload;
const ClientPayload = suharyk.packet.ClientPayload;

const Player = @import("./game/Player.zig");
const Tickable = @import("./game/Tickable.zig");
const VBoard = @import("./game/VBoard.zig");
const SyncCircularQueue = @import("./SyncCircularQueue.zig");
const Duplex = @import("Duplex.zig");

const Game = @This();
const ClientRequest = struct {
    player: *Player,
    pl: *ClientPayload,
};

var gpa: std.heap.DebugAllocator(.{}) = .init;
pub const allocator = gpa.allocator();

pub const tps = 20;

const seed: u64 = undefined;
pub var prng = std.Random.Pcg.init(seed).random();

pub var players: std.ArrayListUnmanaged(*Player) = .empty;
var game_thread: ?std.Thread = null;
// Flyweight pattern
pub var name_list: std.ArrayListUnmanaged([]u8) = .empty;
var cmd_queue: SyncCircularQueue.of(ClientRequest, 512) = .{};
var vboard: VBoard = undefined;
// Observer pattern
// Command pattern
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

pub fn broadcast(player_id: usize, info: anytype) void {
    for (players.items) |player| {
        if (player.id != player_id) {
            player.duplex.send(info) catch |e| {
                // Possibly, connection is closed from other thread or it was half-closed
                std.log.debug("Failed to broadcast: {any}", .{e});
                // std.log.debug("{any}", .{@errorReturnTrace()});
            };
        }
    }
}

pub inline fn playerCount() usize {
    return players.items.len;
}

pub inline fn gameStarted() bool {
    return game_thread != null;
}

fn start() void {
    std.log.info("Game started", .{});
    vboard.generate();
    for (players.items) |*player| {
        player.duplex.send(.{
            .GameStarted = .{
                .device = player.device,
            },
        });
    }
}
