const std = @import("std");

const allocator = @import("game.zig").allocator;

const GameState = @This();

ctx_alignment: u8,
ctx_size: u16,
ctx: *anyopaque,
vtable: *const VTable,

pub const VTable = struct {
    draw: *const fn (ctx: *anyopaque) void,
    deinit: *const fn (ctx: *anyopaque) void,
};

pub inline fn is(self: GameState, T: type) bool {
    const second_vt: VTable = @field(T, "state_vt");
    return self.vtable.draw == second_vt.draw;
}

// Template method pattern
pub inline fn init(T: type) std.mem.Allocator.Error!GameState {
    const ptr = try allocator.create(T);
    ptr.* = T{};
    return .{
        .ctx_alignment = @alignOf(T),
        .ctx_size = @sizeOf(T),
        .ctx = ptr,
        .vtable = &@field(T, "state_vt"),
    };
}

pub inline fn draw(self: GameState) void {
    self.vtable.draw(self.ctx);
}

pub inline fn deinit(self: *GameState) void {
    self.vtable.deinit(self.ctx);
    if (self.ctx_size == 0) return;
    const non_const_ptr = @as([*]u8, @ptrCast(@constCast(self.ctx)));
    std.log.debug("Freeing {d} bytes", .{self.ctx_size});
    allocator.rawFree(
        non_const_ptr[0..self.ctx_size],
        .fromByteUnits(self.ctx_alignment),
        @returnAddress(),
    );
}
