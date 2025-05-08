const std = @import("std");

const GameState = @import("GameState.zig");
const window = @import("window.zig");
const allocator = @import("game.zig").allocator;
const rl = window.rl;
const game = @import("game.zig");

const HackGameState = @This();

pub const state_vt: GameState.VTable = .{
    .draw = draw,
    .deinit = deinit,
    .init = init,
};

pub fn draw(_: *anyopaque) void {}

pub fn init() std.mem.Allocator.Error!GameState {
    return GameState.init(HackGameState);
}

pub fn deinit(ctx: *anyopaque) void {
    _ = &ctx;
}
