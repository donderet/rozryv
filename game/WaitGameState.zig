const std = @import("std");

const allocator = @import("game.zig").allocator;
const GameState = @import("GameState.zig");
const window = @import("window.zig");
const rl = window.rl;
const string = @import("str.zig");
const game = @import("game.zig");
const suharyk = @import("suharyk");
const ClientPayload = suharyk.packet.ClientPayload;

const WaitGameState = @This();

player_list: std.ArrayListUnmanaged([*:0]u8) = .empty,

pub const state_vt: GameState.VTable = .{
    .draw = draw,
    .deinit = deinit,
    .init = init,
};

pub fn draw(ctx: *anyopaque) void {
    var self: *WaitGameState = @ptrCast(@alignCast(ctx));
    _ = &self;
    const label = "Waiting for players...";
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
    const obj_height = window.height / 2;
    const obj_count = 1;
    var obj_rect: rl.Rectangle = .{
        .height = obj_height,
        .width = obj_width,
        .y = (window.height - (obj_height * obj_count + (obj_spacing * (obj_count - 1)))) / 2,
        .x = window.width / 2 - obj_width / 2,
    };
    rl.DrawTextEx(
        window.font,
        "Players",
        .{
            .x = obj_rect.x,
            .y = obj_rect.y - obj_spacing,
        },
        obj_spacing / 2,
        0,
        rl.WHITE,
    );

    rl.DrawRectangleLines(
        @intFromFloat(obj_rect.x),
        @intFromFloat(obj_rect.y),
        @intFromFloat(obj_rect.width),
        @intFromFloat(obj_rect.height),
        rl.WHITE,
    );

    var btn_rect: rl.Rectangle = obj_rect;
    btn_rect.y += obj_spacing;
    btn_rect.y += obj_rect.height;
    btn_rect.height = 100;

    if (game.is_host and self.player_list.items.len >= 2) {
        if (rl.GuiButton(btn_rect, "Start game") == 1) {
            tryStart();
        }
    }

    const text_margin = 8;
    obj_rect.width -= text_margin * 2;
    obj_rect.height -= text_margin * 2;
    obj_rect.y += text_margin;
    obj_rect.x += text_margin;
    const el_color = rl.GetColor(@bitCast(rl.GuiGetStyle(rl.LISTVIEW, rl.TEXT_COLOR_NORMAL)));
    for (self.player_list.items, 1..) |p_name, i| {
        const t_height = 16;
        if (obj_rect.y + t_height < obj_rect.height) {
            rl.DrawTextEx(
                window.font,
                p_name,
                .{ .x = obj_rect.x, .y = obj_rect.y },
                t_height,
                0,
                el_color,
            );
            obj_rect.y += t_height;
            continue;
        }
        var buf: [16]u8 = undefined;
        const more_text = std.fmt.bufPrint(
            &buf,
            "And {d} more",
            .{self.player_list.items.len - i},
        ) catch unreachable;
        rl.DrawTextEx(
            window.font,
            more_text.ptr,
            .{ .x = obj_rect.x, .y = obj_rect.y },
            t_height,
            0,
            el_color,
        );
    }
    self.onDraw() catch |e| {
        std.log.debug("onDraw err: {any}", .{e});
    };
}

fn onDraw(self: *WaitGameState) !void {
    _ = &self;
    while (game.spl_queue.dequeue()) |spl| {
        switch (spl) {
            .BroadcastJoin => |join| {
                const name = try allocator.dupeZ(u8, join.name);
                game.duplex.freePacket(spl);
                try self.player_list.append(allocator, name);
            },
            .BroadcastLeave => |leave| {
                defer game.duplex.freePacket(spl);
                for (self.player_list.items[1..], 1..) |name, i| {
                    if (std.mem.eql(u8, name[0..string.len(name[0..16])], leave.name)) {
                        _ = self.player_list.orderedRemove(i);
                    }
                }
            },
            .GameStarted => {
                game.changeState(@import("HackGameState.zig").init() catch |e| {
                    std.log.debug("Failed to change state: {any}", .{e});
                    game.changeState(@import("MenuGameState.zig").init());
                    game.disconnect();
                    return;
                });
            },
            else => |pl| {
                std.log.debug("Unexpected message from server: {s}", .{@tagName(pl)});
            },
        }
    }
}

pub fn init() std.mem.Allocator.Error!GameState {
    const ptr = try GameState.init(WaitGameState);
    const state: *WaitGameState = @ptrCast(@alignCast(ptr.ctx));
    try state.player_list.append(game.allocator, &game.settings.player_name_buf);
    return ptr;
}

pub fn deinit(ctx: *anyopaque) void {
    _ = &ctx;
    game.stopServer();
}

pub fn tryStart() void {
    std.log.debug("Trying to enqueue request", .{});
    game.cpl_queue.enqueueWait(.{
        .StartGame = {},
    });
}
