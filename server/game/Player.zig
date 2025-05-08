const std = @import("std");

const suharyk = @import("suharyk");
const ServerPayload = suharyk.packet.ServerPayload;
const ClientPayload = suharyk.packet.ClientPayload;
const Virus = @import("Virus.zig");
const Module = suharyk.entities.Virus.Module;

const Duplex = @import("../Duplex.zig");
const Game = @import("../Game.zig");
const SyncCircularQueue = suharyk.SyncCircularQueue;
const Device = @import("Device.zig");
const VBoard = @import("VBoard.zig");

const Player = @This();

pub const DevicePermission = enum {
    View,
    Control,
    PermanentControl,
};

allocator: std.mem.Allocator,
duplex: *Duplex,
done_reading: bool = false,
done_writing: bool = false,
server_req_queue: SyncCircularQueue.of(ServerPayload, 128) = .{},
id: usize,

is_host: bool = false,
name: []u8,
money_amount: u64 = 300,
device: *Device = undefined,
controlled_ips: std.AutoHashMapUnmanaged(u32, DevicePermission) = .empty,
upgrades: [Module.count]u16 = .{0} ** Module.count,
upgrade_cost: [Module.count]u64 = getDefaultUpgradePrices(),
use_count_arr: [Module.count]usize = .{0} ** Module.count,

pub fn getDefaultUpgradePrices() [Module.count]u64 {
    var prices: [Module.count]u64 = undefined;
    for (0..Module.count) |i| {
        prices[i] = getModuleBaseCost(@enumFromInt(i));
    }
    return prices;
}

fn getModuleBaseCost(module: Module) u64 {
    return switch (module) {
        .Worm => 900,
        .ZeroDay => 3000,
        .Rootkit => 600,
        .Rat => 300,
        .Scout => 100,
        .Stealer => 100,
        .Obfuscator => 1000,
    };
}

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
    std.log.debug("Trying to start game...", .{});
    if (!player.is_host) {
        player.server_req_queue.enqueueWait(.{
            .Error = .IllegalSuharyk,
        });
        return;
    }
    if (Game.gameStarted()) return;
    const t = try std.Thread.spawn(
        .{},
        Game.start,
        .{},
    );
    t.detach();
}

pub fn deinit(player: *Player) void {
    _ = Game.name_list.swapRemove(player.id);
    while (!player.isDuplexDead()) {}
    player.allocator.free(player.name);
}

pub fn isDuplexDead(player: Player) bool {
    return player.done_reading and player.done_writing;
}

/// Tries to send any enqueued messages to player's duplex
/// Player instance must be valid until done_writing
pub fn duplexSendLoop(player: *Player) !void {
    defer player.done_writing = true;
    var players = &Game.players;
    defer {
        player.duplex.suharyk_duplex.deinit();
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
    loop: while (true) {
        while (player.server_req_queue.dequeue()) |req| {
            player.duplex.send(req) catch |e| switch (e) {
                error.ConnectionResetByPeer,
                error.BrokenPipe,
                => break :loop,
                else => {
                    std.log.debug("dup rcv err: {any}", .{e});
                    return;
                },
            };
            if (req == .Error or req == .GameOver or req == .Victory) {
                break;
            }
        }
        std.Thread.sleep(std.time.ns_per_ms);
    }
}

/// Tries to enqueue any messages sent to player's duplex
/// Player instance must be valid until done_reading
pub fn duplexRecieveLoop(player: *Player) void {
    defer player.done_reading = true;
    loop: while (true) {
        if (Game.playerCount() == 0) return;
        var pl: suharyk.packet.ClientPayload = undefined;
        player.duplex.recieve(&pl) catch |e| switch (e) {
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
                std.log.debug("dup rcv err: {any}", .{e});
                return;
            },
        };
        if (pl == .StartGame) player.startGame() catch |e| {
            std.log.debug("Can't start game: {any}", .{e});
            Game.disconnectEveryone();
            return;
        };

        if (pl == .Leave) {
            std.log.debug("Got Leave packet", .{});
            break;
        }
        Game.cmd_queue.enqueueWait(.{
            .player = player,
            .pl = pl,
        });
    }
}

pub fn addMoney(self: *Player, amount: u64) void {
    self.money_amount += amount;
    self.updateClientMoney();
}

pub fn removeMoney(self: *Player, amount: u64) void {
    self.money_amount -= amount;
    self.updateClientMoney();
}

fn updateClientMoney(self: *Player) void {
    self.server_req_queue.enqueueWait(.{
        .UpdateMoney = .{
            .new_amount = self.money_amount,
        },
    });
}

pub fn kickForIllegalPacket(player: *Player) void {
    std.log.info(
        "Kicked player {s} for an illegal packet",
        .{player.name},
    );
    player.server_req_queue.enqueueWait(.{
        .Error = .IllegalSuharyk,
    });
}

pub fn createVirus(player: *Player, v: suharyk.entities.Virus) !void {
    const permission = player.controlled_ips.get(v.origin_ip) orelse {
        player.kickForIllegalPacket();
        return;
    };
    if ((v.origin_ip == player.device.suh_entity.ip and permission == .View and std.mem.containsAtLeastScalar(
        Module,
        v.modules,
        1,
        .ZeroDay,
    )) or permission == .View) {
        player.kickForIllegalPacket();
        return;
    }

    const virus = Virus.init(player, v);
    var heap_virus = try Game.allocator.create(Virus);
    heap_virus.* = virus;
    heap_virus.heap_ptr = heap_virus;
    try Game.on_tick.append(Game.allocator, heap_virus.randomTickable().asTickable());
}

pub fn upgradeModule(player: *Player, module: Module) void {
    const i = @intFromEnum(module);
    const max_lvl = std.math.maxInt(@typeInfo(@TypeOf(player.upgrades)).array.child);
    if (player.upgrades[i] == max_lvl) {
        player.kickForIllegalPacket();
        return;
    }
    if (player.upgrade_cost[i] > player.money_amount) {
        player.kickForIllegalPacket();
        return;
    }
    player.money_amount -= player.upgrade_cost[i];
    player.upgrade_cost[i] = player.calcModuleUpgradeCost(module);
    player.server_req_queue.enqueueWait(.{
        .UpdateModuleCost = .{
            .module_cost = player.upgrade_cost,
        },
    });
    player.upgrades[i] += 1;
    player.use_count_arr[i] = 0;
}

fn calcModuleUpgradeCost(player: *Player, module: Module) u64 {
    const current_cost = player.upgrade_cost[@intFromEnum(module)];
    var current_lvl = player.upgrades[@intFromEnum(module)];
    if (current_lvl >= 64) current_lvl = 63;
    return getModuleBaseCost(module) + current_cost / (std.math.pow(u64, 2, current_lvl)) + Game.prng.uintAtMost(u64, 200);
}

pub fn tear(player: *Player, target_ip: u32) !void {
    if (player.controlled_ips.get(target_ip) != .View) {
        player.kickForIllegalPacket();
        return;
    }
    for (Game.players.items) |target_p| {
        if (target_p.device.suh_entity.ip != target_ip) continue;
        target_p.server_req_queue.enqueueWait(.{
            .GameOver = {},
        });
    }
}
