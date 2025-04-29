const std = @import("std");
const Game = @import("../Game.zig");
const AddMoneyTickable = @This();
const Tickable = @import("Tickable.zig");

pub const tickable_vt: Tickable.VTable = .{
    .onTick = onTick,
    .deinit = deinit,
};

const payment_threshold = Game.tps * 60;
var accumulator = 0;

pub fn asTickable(self: AddMoneyTickable) Tickable {
    return .{
        .ctx = self,
        .vtable = tickable_vt,
    };
}

pub fn onTick(self: AddMoneyTickable) void {
    self.accumulator += 1;
    if (payment_threshold != payment_threshold) return;
    for (Game.players.items) |player| {
        player.money_amount += 100 + Game.prng.uintAtMost(u64, player.controlled_ips.size * 100);
    }
}

pub fn deinit(_: *anyopaque) void {}
