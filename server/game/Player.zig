const std = @import("std");

const suharyk = @import("suharyk");

const Game = @import("../Game.zig");
const Duplex = @import("../Duplex.zig");

const Player = @This();

allocator: std.mem.Allocator,
duplex: *Duplex,
id: usize,
disconnect: bool = false,

is_host: bool = false,
name: []u8,
money_amount: usize = 0,

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
