const std = @import("std");

const GameState = @import("GameState.zig");

pub const rl = @cImport({
    @cInclude("raylib.h");
    @cInclude("raygui.h");
});

pub var width: f32 = 0;
pub var height: f32 = 0;
pub var font: rl.Font = undefined;

pub fn onBeginDrawing() void {
    height = @floatFromInt(rl.GetRenderHeight());
    width = @floatFromInt(rl.GetRenderWidth());
    font = rl.GuiGetFont();
    const camera: rl.Camera2D = .{
        .offset = .{
            .x = 0,
            .y = 0,
        },
        .target = .{
            .x = 0,
            .y = 0,
        },
        .rotation = 0,
        .zoom = rl.GetWindowScaleDPI().x,
    };
    rl.BeginMode2D(camera);
    defer rl.EndMode2D();
    rl.ClearBackground(.{ .r = 0, .g = 0, .b = 0, .a = 255 });
}

pub fn isMousePressedOnRect(rect: rl.Rectangle) bool {
    return rl.IsMouseButtonPressed(
        rl.MOUSE_LEFT_BUTTON,
    ) and rl.CheckCollisionPointRec(
        rl.GetMousePosition(),
        rect,
    );
}

pub fn drawCenteredText(
    text: [:0]const u8,
    fs: f32,
    off_x: f32,
    off_y: f32,
    center_v: bool,
    center_h: bool,
    color: rl.Color,
) void {
    const text_dim = rl.MeasureTextEx(font, text, fs, 0);
    const center_off_x = if (center_v) @divTrunc(width - text_dim.x, 2) else 0;
    const center_off_y = if (center_h) @divTrunc(height - text_dim.y, 2) else 0;
    // Account for mantissa error
    if (text_dim.x > width + 0.1) {
        drawCenteredText(
            text,
            fs * width / text_dim.x,
            off_x,
            off_y,
            center_v,
            center_h,
            color,
        );
        return;
    }
    rl.DrawTextEx(
        font,
        text,
        .{
            .x = off_x + center_off_x,
            .y = off_y + center_off_y,
        },
        fs,
        0,
        color,
    );
}
