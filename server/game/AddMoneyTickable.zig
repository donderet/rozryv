const std = @import("std");

const Game = @import("../Game.zig");
const Tickable = @import("Tickable.zig");

const AddMoneyTickable = @This();

pub const tickable_vt: Tickable.VTable = .{
    .onTick = onTick,
    .deinit = deinit,
};

const num_t = u16;
const payment_threshold: num_t = Game.tps * 60;

accumulator: num_t = 0,

pub fn asTickable(self: *AddMoneyTickable) Tickable {
    return .{
        .ctx = self,
        .vtable = &tickable_vt,
    };
}

pub fn onTick(ctx: *anyopaque, _: *bool) void {
    var self: *AddMoneyTickable = @ptrCast(@alignCast(ctx));
    self.accumulator += 1;
    if (self.accumulator != payment_threshold) return;
    for (Game.players.items) |player| {
        player.addMoney(
            100 + Game.prng.uintAtMost(u64, player.controlled_ips.size * 100),
        );
    }
}

pub fn deinit(_: *anyopaque) void {}
