const std = @import("std");
const Tickable = @This();

ctx: *anyopaque,
vtable: *const VTable,

pub const VTable = struct {
    onTick: *const fn (ctx: *anyopaque) void,
};

pub fn onTick(self: Tickable) void {
    self.vtable.onTick(self.ctx);
}
