const std = @import("std");

const GameState = @import("GameState.zig");
const window = @import("window.zig");
const allocator = @import("game.zig").allocator;
const rl = window.rl;
const game = @import("game.zig");

const MenuState = @This();

pub const state_vt: GameState.VTable = .{
    .draw = draw,
    .deinit = deinit,
    .init = init,
};

pub fn draw(_: *anyopaque) void {
    const label = "C.Y.B.E.R. R.O.Z.R.Y.V.";
    window.drawCenteredText(
        label,
        32,
        0,
        50,
        true,
        false,
        rl.WHITE,
    );
    const btn_width = 300;
    const btn_spacing = 20;
    const btn_height = window.height / 8;
    const obj_count = 2;
    var btn_rect: rl.Rectangle = .{
        .height = btn_height,
        .width = btn_width,
        .y = (window.height - (btn_height * obj_count + (btn_spacing * (obj_count - 1)))) / 2,
        .x = window.width / 2 - btn_width / 2,
    };
    _ = rl.GuiButton(btn_rect, "Host game");
    btn_rect.y += btn_spacing;
    btn_rect.y += btn_rect.height;

    if (rl.GuiButton(btn_rect, "Join game") == 1) blk: {
        game.state = @import("JoinGameState.zig").init() catch |e| {
            std.log.debug("Failed to set state to JoinGame: {any}", .{e});
            break :blk;
        };
    }
}

pub fn init() std.mem.Allocator.Error!GameState {
    return GameState.init(MenuState);
}

pub fn deinit(ctx: *anyopaque) void {
    _ = &ctx;
}
