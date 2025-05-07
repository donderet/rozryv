const std = @import("std");

const suharyk = @import("suharyk");
const ServerPayload = suharyk.packet.ServerPayload;
const ClientPayload = suharyk.packet.ClientPayload;
const Virus = suharyk.entities.Virus;

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
server_req_queue: SyncCircularQueue.of(ServerPayload, 128) = .{},
id: usize,

is_host: bool = false,
name: []u8,
money_amount: u64 = 300,
device: *Device = undefined,
controlled_ips: std.AutoHashMapUnmanaged(u32, DevicePermission) = .empty,
upgrades: [Virus.module_enum_size]u16 = .{0} ** Virus.module_enum_size,
upgrade_cost: [Virus.module_enum_size]u64 = getDefaultUpgradePrices(),
use_count_arr: [Virus.module_enum_size]usize = .{0} ** Virus.module_enum_size,

pub fn getDefaultUpgradePrices() [Virus.module_enum_size]u64 {
    var prices: [Virus.module_enum_size]u64 = undefined;
    for (0..Virus.module_enum_size) |i| {
        prices[i] = getModuleBaseCost(@enumFromInt(i));
    }
    return prices;
}

fn getModuleBaseCost(module: Virus.Module) u64 {
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
    loop: while (true) {
        while (player.server_req_queue.dequeue()) |req| {
            player.duplex.send(req) catch |e| switch (e) {
                error.ConnectionResetByPeer,
                error.BrokenPipe,
                => break :loop,
                else => return e,
            };
            if (req == .Error or req == .GameOver or req == .Victory) {
                player.duplex.suharyk_duplex.deinit();
            }
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
        .player = self,
        .pl = .{
            .UpdateMoney = .{
                .newAmount = self.money_amount,
            },
        },
    });
}

pub fn kickForIllegalPacket(player: *Player) void {
    player.server_req_queue.enqueueWait(.{
        .Error = .IllegalSuharyk,
    });
}

pub fn createVirus(player: *Player, v: suharyk.entities.Virus) !void {
    const virus: Virus = .init(player, v);
    if (v.origin_ip != player.device.suh_entity.ip) {
        const permission = player.controlled_ips.get(v.origin_ip) orelse {
            player.kickForIllegalPacket();
            return;
        };
        if (permission == .View) {
            player.kickForIllegalPacket();
            return;
        }
    }
    try Game.on_tick.append(Game.allocator, virus.randomTickable().asTickable());
}

pub fn upgradeModule(player: *Player, module: Virus.Module) void {
    const i = @intFromEnum(module);
    const max_lvl = std.math.maxInt(@typeInfo(@TypeOf(player.upgrades)).array.child);
    if (player.upgrades[i] == max_lvl) {
        player.kickForIllegalPacket();
        return;
    }
    if (player.upgrade_cost > player.money_amount) {
        player.kickForIllegalPacket();
        return;
    }
    player.money_amount -= player.upgrade_cost;
    player.upgrade_cost[i] = player.calcModuleUpgradeCost(module);
    player.server_req_queue.enqueueWait(.{
        .UpdateModuleCost = .{
            .module_cost = player.upgrade_cost,
        },
    });
    player.upgrades[i] += 1;
    player.use_count_arr[i] = 0;
}

fn calcModuleUpgradeCost(player: *Player, module: Virus.Module) u64 {
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
            .GameOver,
        });
    }
}
