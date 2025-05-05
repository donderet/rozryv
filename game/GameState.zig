const std = @import("std");

const allocator = @import("game.zig").allocator;

const GameState = @This();

ctx: *anyopaque,
vtable: *const VTable,

pub const VTable = struct {
    draw: *const fn (ctx: *anyopaque) void,
    init: *const fn () std.mem.Allocator.Error!GameState,
    deinit: *const fn (ctx: *anyopaque) void,
};

pub inline fn init(T: type) std.mem.Allocator.Error!GameState {
    const ptr = try allocator.create(T);
    ptr.* = T{};
    return .{
        .ctx = ptr,
        .vtable = &@field(T, "state_vt"),
    };
}

pub inline fn draw(self: GameState) void {
    self.vtable.draw(self.ctx);
}

pub inline fn deinit(self: GameState) void {
    self.vtable.deinit(self.ctx);
}
