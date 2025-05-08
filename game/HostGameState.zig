const std = @import("std");

const allocator = @import("game.zig").allocator;
const GameState = @import("GameState.zig");
const window = @import("window.zig");
const rl = window.rl;
const string = @import("str.zig");
const game = @import("game.zig");

const HostGameState = @This();

name_buf: [15:0]u8 = @splat(0),

pub const state_vt: GameState.VTable = .{
    .draw = draw,
    .deinit = deinit,
    .init = init,
};

pub fn draw(ctx: *anyopaque) void {
    var self: *HostGameState = @ptrCast(ctx);
    _ = &self;
    const label = "Host game";
    window.drawCenteredText(
        label,
        32,
        0,
        50,
        true,
        false,
        rl.WHITE,
    );
    const obj_width = 300;
    const obj_spacing = 20;
    const obj_height = window.height / 8;
    const obj_count = 2;
    var obj_rect: rl.Rectangle = .{
        .height = obj_height,
        .width = obj_width,
        .y = (window.height - (obj_height * obj_count + (obj_spacing * (obj_count - 1)))) / 2,
        .x = window.width / 2 - obj_width / 2,
    };
    rl.DrawTextEx(
        window.font,
        "Display name",
        .{
            .x = obj_rect.x,
            .y = obj_rect.y - obj_spacing,
        },
        obj_spacing / 2,
        0,
        rl.WHITE,
    );

    if (rl.GuiTextBox(
        obj_rect,
        &self.name_buf,
        self.name_buf.len,
        true,
    ) == 1) {
        self.tryHost();
    }
    obj_rect.y += obj_spacing;
    obj_rect.y += obj_rect.height;

    if (rl.GuiButton(obj_rect, "Host") == 1) {
        self.tryHost();
    }
}

pub fn init() std.mem.Allocator.Error!GameState {
    const ptr = try GameState.init(HostGameState);
    const state: *HostGameState = @ptrCast(@alignCast(ptr.ctx));
    state.name_buf = game.settings.player_name_buf;
    return ptr;
}

pub fn deinit(ctx: *anyopaque) void {
    _ = &ctx;
}

pub fn tryHost(self: *HostGameState) void {
    if (self.name_buf[0] == 0) return;
    const name = self.name_buf[0..string.len(&self.name_buf)];
    game.settings.setPlayerName(name);
    game.startServer() catch |e| {
        std.log.debug("Failed to start server: {any}", .{e});
        return;
    };
    for (0..16) |_| {
        const addr = std.net.Address.initIp4(.{ 127, 0, 0, 1 }, 6000);
        @import("JoinGameState.zig").enterWaitRoom(
            addr,
        ) catch |e| {
            std.log.debug("Can't join: {any}", .{e});
            std.Thread.sleep(100 * std.time.ns_per_ms);
            continue;
        };
        break;
    }
}
