const std = @import("std");

const Game = @import("../Game.zig");
const Tickable = @import("Tickable.zig");

const RandomTickable = @This();

pub const tickable_vt: Tickable.VTable = .{
    .onTick = onTick,
    .deinit = deinit,
};

pub const VTable = struct {
    /// Avarage interval between events in seconds
    interval: u16,
    /// Execute random event and return whether to consider Tickable dead
    onRandomTick: *const fn (ctx: *anyopaque, dead_ptr: *bool) void,
    deinit: *const fn (ctx: *anyopaque) void,
};

ctx: *anyopaque,
vtable: *const VTable,
accumulated_ticks: u8 = 0,

pub inline fn onRandomTick(ctx: *anyopaque, dead_ptr: *bool) void {
    var self: *RandomTickable = @ptrCast(@alignCast(ctx));
    self.vtable.onRandomTick(self.ctx, dead_ptr);
}

pub fn onTick(ctx: *anyopaque, dead_ptr: *bool) void {
    const self: *RandomTickable = @ptrCast(@alignCast(ctx));
    var should_run: bool = undefined;
    if (self.vtable.interval != 0) {
        self.accumulated_ticks += 1;
        if (self.accumulated_ticks != Game.tps) return;
        self.accumulated_ticks = 0;
        should_run = Game.prng.intRangeLessThan(u16, 0, self.vtable.interval) == 0;
    } else {
        should_run = true;
    }
    if (should_run) {
        onRandomTick(self, dead_ptr);
    }
}

// Adapter pattern
pub inline fn asTickable(self: *RandomTickable) Tickable {
    return .{
        .ctx = self,
        .vtable = &tickable_vt,
    };
}

pub fn deinit(ctx: *anyopaque) void {
    const self: *RandomTickable = @ptrCast(@alignCast(ctx));
    self.vtable.deinit(self.ctx);
}
