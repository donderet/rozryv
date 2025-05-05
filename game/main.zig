const std = @import("std");
const GameState = @import("GameState.zig");
const game = @import("game.zig");
const window = @import("window.zig");
const rl = window.rl;

pub fn main() !void {
    game.state = try @import("MenuState.zig").state_vt.init();
    rl.SetConfigFlags(rl.FLAG_WINDOW_RESIZABLE);
    rl.SetTraceLogLevel(rl.LOG_WARNING);
    rl.SetExitKey(0);
    rl.InitWindow(800, 800, "C.Y.B.E.R. R.O.Z.R.Y.V.");
    defer rl.CloseWindow();
    rl.SetTargetFPS(60);
    rl.GuiLoadStyle("assets/rozryv.rgs");
    rl.GuiSetStyle(rl.DEFAULT, rl.TEXT_SIZE, 24);
    while (!rl.WindowShouldClose()) {
        rl.BeginDrawing();
        window.onBeginDrawing();
        defer rl.EndDrawing();
        game.state.draw();
    }
}

fn menu() void {}
