const std = @import("std");

const allocator = @import("game.zig").allocator;
const game = @import("game.zig");
const GameState = @import("GameState.zig");
const window = @import("window.zig");
const rl = window.rl;

const MsgGameState = @This();

msg: [:0]const u8,

pub const state_vt: GameState.VTable = .{
    .draw = draw,
    .deinit = deinit,
};

pub fn draw(ctx: *anyopaque) void {
    const self: *MsgGameState = @ptrCast(@alignCast(ctx));
    const margin = 15;
    _ = rl.GuiPanel(
        .{
            .x = margin,
            .y = margin,
            .width = window.width - (2 * margin),
            .height = window.height - (2 * margin),
        },
        self.msg,
    );
}

pub fn init(msg: [:0]const u8) std.mem.Allocator.Error!GameState {
    const ptr = try allocator.create(MsgGameState);
    ptr.* = .{
        .msg = msg,
    };
    return .{
        .ctx = ptr,
        .ctx_size = @sizeOf(MsgGameState),
        .ctx_alignment = @alignOf(MsgGameState),
        .vtable = &state_vt,
    };
}

pub fn deinit(ctx: *anyopaque) void {
    _ = &ctx;
}
