const std = @import("std");
const Tickable = @This();

ctx: *anyopaque,
vtable: *const VTable,

pub const VTable = struct {
    dead: bool = false,
    onTick: *const fn (ctx: *anyopaque) void,
    deinit: *const fn (ctx: *anyopaque) void,
};

pub inline fn isDead(self: Tickable) bool {
    return self.vtable.dead;
}

pub fn onTick(self: Tickable) void {
    self.vtable.onTick(self.ctx);
}

pub fn deinit(self: Tickable) void {
    self.vtable.deinit(self.ctx);
}
