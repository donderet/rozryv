const std = @import("std");

const allocator = @import("game.zig").allocator;
const game = @import("game.zig");
const GameState = @import("GameState.zig");
const window = @import("window.zig");
const rl = window.rl;

const MenuGameState = @This();

pub const state_vt: GameState.VTable = .{
    .draw = draw,
    .deinit = deinit,
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
    const obj_count = if (!std.process.can_spawn) 1 else 2;
    var btn_rect: rl.Rectangle = .{
        .height = btn_height,
        .width = btn_width,
        .y = (window.height - (btn_height * obj_count + (btn_spacing * (obj_count - 1)))) / 2,
        .x = window.width / 2 - btn_width / 2,
    };
    if (std.process.can_spawn) {
        if (rl.GuiButton(btn_rect, "Host game") == 1) blk: {
            game.changeState(
                @import("HostGameState.zig").init() catch |e| {
                    std.log.debug("Failed to set state to HostGame: {any}", .{e});
                    break :blk;
                },
            );
        }
        btn_rect.y += btn_spacing;
        btn_rect.y += btn_rect.height;
    }

    if (rl.GuiButton(btn_rect, "Join game") == 1) blk: {
        game.changeState(
            @import("JoinGameState.zig").init() catch |e| {
                std.log.debug("Failed to set state to JoinGame: {any}", .{e});
                break :blk;
            },
        );
    }
}

pub fn init() GameState {
    return .{
        .ctx = undefined,
        .ctx_alignment = 0,
        .ctx_size = 0,
        .vtable = &state_vt,
    };
}

pub fn deinit(ctx: *anyopaque) void {
    _ = &ctx;
    game.player = .{};
}
