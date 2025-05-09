const std = @import("std");

const suharyk = @import("suharyk");

const allocator = @import("game.zig").allocator;
const game = @import("game.zig");
const GameState = @import("GameState.zig");
const string = @import("str.zig");
const window = @import("window.zig");
const rl = window.rl;

const JoinGameState = @This();

name_input_active: bool = true,
ip_input_active: bool = false,
ip_input_invalid: bool = false,
name_buf: [15:0]u8 = @splat(0),
address_buf: [255:0]u8 = @splat(0),

pub const state_vt: GameState.VTable = .{
    .draw = draw,
    .deinit = deinit,
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
    const obj_width = 300;
    const obj_spacing = 20;
    const obj_height = window.height / 8;
    const obj_count = 3;
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
    if (window.isMousePressedOnRect(obj_rect)) {
        self.name_input_active = true;
        self.ip_input_active = false;
    }

    if (rl.GuiTextBox(
        obj_rect,
        &self.name_buf,
        self.name_buf.len,
        self.name_input_active,
    ) == 1) {
        self.name_input_active = false;
        self.ip_input_active = true;
    }
    obj_rect.y += obj_spacing;
    obj_rect.y += obj_rect.height;

    rl.DrawTextEx(
        window.font,
        "IP and port",
        .{
            .x = obj_rect.x,
            .y = obj_rect.y - obj_spacing,
        },
        obj_spacing / 2,
        0,
        rl.WHITE,
    );
    if (window.isMousePressedOnRect(obj_rect)) {
        self.name_input_active = false;
        self.ip_input_active = true;
    }
    var def_color: c_int = undefined;
    if (self.ip_input_invalid) {
        def_color = rl.GuiGetStyle(rl.DEFAULT, rl.TEXT_COLOR_PRESSED);
        rl.GuiSetStyle(rl.DEFAULT, rl.TEXT_COLOR_PRESSED, @bitCast(rl.RED));
    }
    const pressed_enter = rl.GuiTextBox(
        obj_rect,
        &self.address_buf,
        self.address_buf.len,
        self.ip_input_active,
    ) == 1;
    if (self.ip_input_invalid) {
        rl.GuiSetStyle(rl.DEFAULT, rl.TEXT_COLOR_PRESSED, def_color);
    }
    obj_rect.y += obj_spacing;
    obj_rect.y += obj_rect.height;

    const pressed_btn = rl.GuiButton(obj_rect, "Join") == 1;
    defer if (pressed_enter or pressed_btn) {
        self.tryJoin();
    };
}

pub fn init() std.mem.Allocator.Error!GameState {
    const ptr = try GameState.init(JoinGameState);
    const state: *JoinGameState = @ptrCast(@alignCast(ptr.ctx));
    state.name_buf = game.settings.player_name_buf;
    state.address_buf = game.settings.last_address_buf;
    return ptr;
}

pub fn deinit(ctx: *anyopaque) void {
    _ = &ctx;
}

pub fn tryJoin(self: *JoinGameState) void {
    if (self.name_buf[0] == 0) {
        self.name_input_active = true;
        self.ip_input_active = false;
        return;
    }
    if (self.address_buf[0] == 0) {
        self.name_input_active = false;
        self.ip_input_active = true;
        return;
    }
    const name = self.name_buf[0..string.len(&self.name_buf)];
    game.settings.setPlayerName(name);
    const ip_buf_len = string.len(&self.address_buf);
    const input = self.address_buf[0..ip_buf_len];
    game.settings.setLastAddress(input);
    const port_i = string.indexOfBackwards(input, ':');
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
        enterWaitRoom(addr_list.addrs[0]) catch break :blk;
        return;
    }
    self.ip_input_invalid = true;
}

pub fn enterWaitRoom(addr: std.net.Address) !void {
    try game.join(addr);
    const WaitState = @import("WaitGameState.zig");
    const state = WaitState.init() catch |e| {
        std.log.debug("Error while setting state to WaitState: {any}", .{e});
        game.stopServer();
        return e;
    };
    const wait_state: *WaitState = @ptrCast(@alignCast(state.ctx));
    var server_hello: suharyk.server_hello = undefined;
    try game.duplex.suharyk_duplex.recieve(&server_hello);
    defer game.duplex.suharyk_duplex.freePacket(server_hello);
    if (!server_hello.ok) return error.NotOk;
    const players: [][]u8 = server_hello.members.?;
    if (players.len == 0) {
        game.player.is_host = true;
    } else {
        std.log.debug("Players in game: {d}", .{players.len});
        for (players) |name| {
            std.log.debug("name: {s}", .{name});
            const name_z = try game.allocator.dupeZ(u8, name);
            try wait_state.player_list.append(allocator, name_z.ptr);
        }
    }
    game.changeState(state);
    try game.startDuplexLoop();
    std.log.debug("Changed state", .{});
}
