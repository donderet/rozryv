const std = @import("std");

const allocator = @import("game.zig").allocator;
const GameState = @import("GameState.zig");
const window = @import("window.zig");
const rl = window.rl;
const string = @import("str.zig");
const game = @import("game.zig");

const JoinGameState = @This();

name_input_active: bool = true,
ip_input_active: bool = false,
ip_input_invalid: bool = false,
name_buf: [16]u8 = @splat(0),
ip_buf: [1024]u8 = @splat(0),

pub const state_vt: GameState.VTable = .{
    .draw = draw,
    .deinit = deinit,
    .init = init,
};

pub fn draw(ctx: *anyopaque) void {
    var self: *JoinGameState = @ptrCast(ctx);
    _ = &self;
    const label = "Join game";
    window.drawCenteredText(
        label,
        32,
        0,
        50,
        true,
        false,
        rl.WHITE,
    );
    const tf_width = 300;
    const tf_spacing = 20;
    const tf_height = window.height / 8;
    const obj_count = 3;
    var tf_rect: rl.Rectangle = .{
        .height = tf_height,
        .width = tf_width,
        .y = (window.height - (tf_height * obj_count + (tf_spacing * (obj_count - 1)))) / 2,
        .x = window.width / 2 - tf_width / 2,
    };
    rl.DrawTextEx(
        window.font,
        "Display name",
        .{
            .x = tf_rect.x,
            .y = tf_rect.y - tf_spacing,
        },
        tf_spacing / 2,
        0,
        rl.WHITE,
    );
    if (window.isMousePressedOnRect(tf_rect)) {
        self.name_input_active = true;
        self.ip_input_active = false;
    }

    if (rl.GuiTextBox(
        tf_rect,
        &self.name_buf,
        self.name_buf.len,
        self.name_input_active,
    ) == 1) {
        self.name_input_active = false;
        self.ip_input_active = true;
    }
    tf_rect.y += tf_spacing;
    tf_rect.y += tf_rect.height;

    rl.DrawTextEx(
        window.font,
        "IP and port",
        .{
            .x = tf_rect.x,
            .y = tf_rect.y - tf_spacing,
        },
        tf_spacing / 2,
        0,
        rl.WHITE,
    );
    if (window.isMousePressedOnRect(tf_rect)) {
        self.name_input_active = false;
        self.ip_input_active = true;
    }
    var def_color: c_int = undefined;
    if (self.ip_input_invalid) {
        def_color = rl.GuiGetStyle(rl.DEFAULT, rl.TEXT_COLOR_PRESSED);
        rl.GuiSetStyle(rl.DEFAULT, rl.TEXT_COLOR_PRESSED, @bitCast(rl.RED));
    }
    if (rl.GuiTextBox(
        tf_rect,
        &self.ip_buf,
        self.ip_buf.len,
        self.ip_input_active,
    ) == 1) {
        self.tryJoin();
    }
    if (self.ip_input_invalid) {
        rl.GuiSetStyle(rl.DEFAULT, rl.TEXT_COLOR_PRESSED, def_color);
    }
    tf_rect.y += tf_spacing;
    tf_rect.y += tf_rect.height;

    if (rl.GuiButton(tf_rect, "Join") == 1) {
        self.tryJoin();
    }
}

pub fn init() std.mem.Allocator.Error!GameState {
    return GameState.init(JoinGameState);
}

pub fn deinit(ctx: *anyopaque) void {
    _ = &ctx;
}

pub fn tryJoin(self: *JoinGameState) void {
    std.log.debug("Try join", .{});
    if (self.name_buf[0] == 0) {
        self.name_input_active = true;
        self.ip_input_active = false;
        return;
    }
    const ip_buf_len = string.len(&self.ip_buf);
    std.log.debug("ip buf len: {d}", .{ip_buf_len});
    const input = self.ip_buf[0..ip_buf_len];
    const port_i = string.indexOfBackwards(input, ':');
    std.log.debug("Index of ':' in {s}: {d}", .{ input, port_i });
    if (port_i != 0) blk: {
        if (port_i == input.len - 1) break :blk;
        const unresolved_address = input[0..port_i];
        const port_str = input[port_i + 1 ..];
        const port = std.fmt.parseInt(u16, port_str, 10) catch break :blk;
        const addr_list = std.net.getAddressList(
            game.allocator,
            unresolved_address,
            port,
        ) catch |e| {
            std.log.debug("Failed to get address list for {s}: {any}", .{ unresolved_address, e });
            break :blk;
        };
        defer addr_list.deinit();
        if (addr_list.addrs.len == 0) break :blk;
        std.log.debug("Resolved to: {d}", .{addr_list.addrs[0].in.sa.addr});
        joinGame(addr_list.addrs[0]) catch {
            break :blk;
        };
        return;
    }
    self.ip_input_invalid = true;
}

pub fn joinGame(addr: std.net.Address) !void {
    var t = try std.net.tcpConnectToAddress(addr);
    std.Thread.sleep(1000);
    t.close();
}
