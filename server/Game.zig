const std = @import("std");

const suharyk = @import("suharyk");
const entities = suharyk.entities;
const Device = entities.Device;
const ServerPayload = suharyk.packet.ServerPayload;
const ClientPayload = suharyk.packet.ClientPayload;
const SyncCircularQueue = suharyk.SyncCircularQueue;

const AddMoneyTickable = @import("./game/AddMoneyTickable.zig");
const Player = @import("./game/Player.zig");
const Tickable = @import("./game/Tickable.zig");
const VBoard = @import("./game/VBoard.zig");
const Duplex = @import("Duplex.zig");

const Game = @This();

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
var pcg = std.Random.Pcg.init(seed);
pub var prng = pcg.random();

pub var players: std.ArrayListUnmanaged(*Player) = .empty;
var game_started = false;
pub var name_list: std.ArrayListUnmanaged([]u8) = .empty;
pub var cmd_queue: SyncCircularQueue.of(ClientRequest, 512) = .{};
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
            player.server_req_queue.enqueueWait(info);
        }
    }
}

pub inline fn playerCount() usize {
    return players.items.len;
}

pub inline fn gameStarted() bool {
    return game_started;
}

pub fn ipToIndex(ip: u32) ?usize {
    return VBoard.index_lut.get(ip);
}

pub fn disconnectEveryone() void {
    for (players.items) |player| {
        player.duplex.suharyk_duplex.deinit();
    }
}

pub fn start() void {
    std.log.info("Game started", .{});
    game_started = true;
    var money_rtkbl: AddMoneyTickable = .{};
    const money_tickable = money_rtkbl.asTickable();
    on_tick.append(Game.allocator, money_tickable) catch |e| {
        std.log.debug("Can't append: {any}", .{e});
        disconnectEveryone();
        return;
    };
    VBoard.generate() catch |e| {
        std.log.debug("Can't generate vboard: {any}", .{e});
        disconnectEveryone();
        return;
    };
    for (players.items) |player| {
        player.server_req_queue.enqueueWait(.{
            .GameStarted = .{
                .player_ip = player.device.suh_entity.ip,
            },
        });
        player.server_req_queue.enqueueWait(.{
            .UpdateModuleCost = .{
                .module_cost = player.upgrade_cost,
            },
        });
        player.server_req_queue.enqueueWait(.{
            .UpdateMoney = .{
                .new_amount = player.money_amount,
            },
        });
        player.controlled_ips.put(
            allocator,
            player.device.suh_entity.ip,
            .PermanentControl,
        ) catch |e| {
            std.log.debug("Can't add player to its own cotnrolled ips: {any}", .{e});
            disconnectEveryone();
            return;
        };
    }
    var timer = std.time.Timer.start() catch {
        @panic("Timer is not supported");
    };
    game_loop: while (true) {
        if (playerCount() == 0) break;

        while (cmd_queue.dequeue()) |cmd| {
            defer cmd.player.duplex.freePacket(cmd.pl);
            handleRequest(cmd.pl, cmd.player) catch |e| {
                std.log.debug("Error while handling request: {any}", .{e});
                break :game_loop;
            };
        }

        var i: usize = 0;
        while (i != on_tick.items.len) {
            const handler: *Tickable = &on_tick.items[i];
            if (handler.dead) {
                handler.deinit();
                _ = on_tick.swapRemove(i);
                continue;
            }
            handler.onTick();
            i += 1;
        }

        if (Game.playerCount() == 1) {
            players.items[0].server_req_queue.enqueueWait(.{
                .Victory = {},
            });
        }

        const eepy_time = tick_time -| timer.read();
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
        .StartGame => {
            // Race condition, do nothing, just wait for the client to update itself
        },
        .CreateVirus => |cv| {
            try player.createVirus(cv.virus);
        },
        .UpgradeModule => |um| {
            player.upgradeModule(um.mod);
        },
        .Rozryv => |rozryv| {
            try player.tear(rozryv.target_ip);
        },
    }
}
