const std = @import("std");
const Tickable = @import("Tickable.zig");
const Game = @import("../Game.zig");
const RandomTickable = @This();

ctx: *anyopaque,
vtable: *const VTable,
accumulated_ticks: u8 = 0,

pub const tickable_vt: Tickable.VTable = .{
    .onTick = onTick,
};

pub const VTable = struct {
    /// Avarage interval between events in seconds
    interval: u16,
    onRandomTick: *const fn (ctx: *anyopaque) void,
};

pub fn onRandomTick(self: RandomTickable) void {
    self.vtable.onRandomTick(self.ctx);
}

pub fn onTick(self: RandomTickable) void {
    self.accumulated_ticks += 1;
    if (self.accumulated_ticks != Game.tps) return;
    self.accumulated_ticks = 0;
    const should_run = Game.prng.intRangeLessThan(u16, 0, self.vtable.interval) == 0;
    if (should_run) onRandomTick(self);
}

// Adapter pattern
pub fn asTickable(self: *RandomTickable) Tickable {
    return .{
        .ctx = self,
        .vtable = tickable_vt,
    };
}
