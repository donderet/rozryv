const std = @import("std");
const Tickable = @This();

ctx: *anyopaque,
// Strategy pattern
vtable: *const VTable,
dead: bool = false,

pub const VTable = struct {
    onTick: *const fn (ctx: *anyopaque, dead_ptr: *bool) void,
    deinit: *const fn (ctx: *anyopaque) void,
};

pub fn onTick(self: *Tickable) void {
    if (self.dead) return;
    self.vtable.onTick(self.ctx, &self.dead);
}

pub fn deinit(self: *Tickable) void {
    self.vtable.deinit(self.ctx);
}
