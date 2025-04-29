const std = @import("std");

const suharyk = @import("suharyk");
const entities = suharyk.entities;
const Device = entities.Device;
const ServerPayload = suharyk.packet.ServerPayload;
const ClientPayload = suharyk.packet.ClientPayload;

const AddMoneyTickable = @import("./game/AddMoneyTickable.zig");
const Player = @import("./game/Player.zig");
const Tickable = @import("./game/Tickable.zig");
const VBoard = @import("./game/VBoard.zig");
const SyncCircularQueue = @import("./SyncCircularQueue.zig");
const Duplex = @import("Duplex.zig");

const Game = @This();
// Command pattern
pub const ClientRequest = struct {
    player: *Player,
    pl: ClientPayload,
};

var gpa: std.heap.DebugAllocator(.{}) = .init;
pub const allocator = gpa.allocator();

pub const tps = 20;
/// Time per tick in nanoseconds
const tick_time = std.time.ns_per_s / tps;

const seed: u64 = undefined;
pub var prng = std.Random.Pcg.init(seed).random();

pub var players: std.ArrayListUnmanaged(*Player) = .empty;
var game_thread: ?std.Thread = null;
pub var name_list: std.ArrayListUnmanaged([]u8) = .empty;
pub var cmd_queue: SyncCircularQueue.of(ClientRequest, 512) = .{};
pub var vboard: VBoard = undefined;
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

pub fn ipToIndex(ip: u32) ?usize {
    return vboard.index_lut.get(ip);
}

fn start() void {
    std.log.info("Game started", .{});
    const money_tickable = AddMoneyTickable.asTickable();
    on_tick.append(Game.allocator, money_tickable);
    vboard.generate();
    for (players.items) |*player| {
        player.duplex.send(.{
            .GameStarted = .{
                .device = player.device,
            },
        });
        on_tick.append(
            allocator,
        );
    }
    var timer: std.time.Timer = try .start();
    while (true) {
        if (playerCount() == 0) break;

        while (cmd_queue.dequeue()) |cmd| {
            defer cmd.player.duplex.freePacket(cmd.pl);
            handleRequest(cmd.pl, cmd.player);
        }

        for (on_tick.items, 0..) |handler, i| {
            if (handler.isDead()) {
                handler.deinit();
                _ = on_tick.swapRemove(i);
                continue;
            }
            handler.onTick();
        }

        if (Game.playerCount() == 1) {
            players.items[0].server_req_queue.enqueueWait(.{
                .Victory,
            });
        }

        const eepy_time = tick_time - timer.read();
        if (eepy_time <= 0) {
            std.log.info(
                "Server is overloaded and running {d} ms behind ",
                .{eepy_time / std.time.ns_per_ms},
            );
        } else {
            std.Thread.sleep(eepy_time);
        }
        timer.reset();
    }
}

fn handleRequest(pl: ClientPayload, player: *Player) !void {
    switch (pl) {
        .Leave => unreachable,
        .CreateVirus => |cv| {
            player.createVirus(cv.virus);
        },
        .UpdgradeModule => |um| {
            player.upgradeModule(um.mod);
        },
        .Rozryv => |rozryv| {
            player.tear(rozryv.target_ip);
        },
    }
}
