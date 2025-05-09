const std = @import("std");

const game = @import("game.zig");
const GameState = @import("GameState.zig");
const window = @import("window.zig");
const rl = window.rl;

pub fn main() !void {
    try game.init();
    game.settings.restore() catch |e| {
        std.log.debug("Cannot restore settings: {any}", .{e});
    };
    if (@import("builtin").mode != .Debug) {
        rl.SetConfigFlags(rl.FLAG_WINDOW_RESIZABLE);
    }
    rl.SetTraceLogLevel(rl.LOG_WARNING);
    rl.SetExitKey(0);
    rl.InitWindow(900, 900, "C.Y.B.E.R. R.O.Z.R.Y.V.");
    defer rl.CloseWindow();
    rl.SetTargetFPS(60);
    rl.GuiLoadStyle("assets/rozryv.rgs");
    rl.GuiSetStyle(rl.DEFAULT, rl.TEXT_SIZE, 24);
    while (!rl.WindowShouldClose()) {
        rl.BeginDrawing();
        window.onBeginDrawing();
        defer rl.EndDrawing();
        game.getState().draw();
    }
}
