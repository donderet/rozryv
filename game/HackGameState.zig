const std = @import("std");

const suharyk = @import("suharyk");
const Module = suharyk.entities.Virus.Module;

const allocator = @import("game.zig").allocator;
const DeviceInfo = @import("Player.zig").DeviceInfo;
const game = @import("game.zig");
const GameState = @import("GameState.zig");
const MsgState = @import("MsgGameState.zig");
const window = @import("window.zig");
const rl = window.rl;

const HackGameState = @This();

pub const state_vt: GameState.VTable = .{
    .draw = draw,
    .deinit = deinit,
};

ip_list: std.ArrayListUnmanaged([*c]const u8) = .empty,
list_scroll_index: c_int = 0,
list_active_index: c_int = -1,
list_focus_index: c_int = -1,
modules: [Module.count]bool = @splat(false),
modules_available: [Module.count]bool = @splat(false),
upgrade_text: [Module.count][23:0]u8 = @splat(@splat(0)),
money_text: [31:0]u8 = @splat(0),

active_modules_ser_buf: [Module.count]Module = undefined,

pub fn draw(ctx: *anyopaque) void {
    const self: *HackGameState = @ptrCast(@alignCast(ctx));
    const margin = 15;
    const rect: rl.Rectangle = .{
        .x = margin,
        .y = margin,
        .height = window.height - (2 * margin),
        .width = window.width / 2 - margin,
    };
    _ = rl.GuiListViewEx(
        rect,
        self.ip_list.items.ptr,
        @truncate(@as(i64, @bitCast(self.ip_list.items.len))),
        &self.list_scroll_index,
        &self.list_active_index,
        &self.list_focus_index,
    );
    rl.DrawRectangleLines(
        @intFromFloat(rect.x + rect.width),
        @intFromFloat(rect.y),
        @intFromFloat(rect.width),
        @intFromFloat(rect.height),
        rl.WHITE,
    );
    const money_font_size = margin;
    rl.DrawTextEx(
        window.font,
        &self.money_text,
        .{
            .x = window.width - (margin * 2) - 100,
            .y = rect.y - money_font_size,
        },
        money_font_size,
        0,
        rl.WHITE,
    );
    if (self.list_active_index != -1) {
        const target_info = game.player.controlled_ips.values()[@as(u32, @bitCast(self.list_active_index))];
        const el_color = rl.GetColor(@bitCast(rl.GuiGetStyle(rl.LISTVIEW, rl.TEXT_COLOR_NORMAL)));
        rl.DrawTextEx(
            window.font,
            target_info.desc,
            .{ .x = rect.width + margin, .y = rect.y + margin },
            12,
            0,
            el_color,
        );
        const btn_height = 50;
        const checkbox_height = 25;
        var mod_rect: rl.Rectangle = .{
            .x = rect.width + margin,
            .y = window.height - margin - (Module.count * checkbox_height) - btn_height,
            .height = checkbox_height,
            .width = rect.width,
        };
        const menu_text_height = 18;
        rl.DrawTextEx(
            window.font,
            "SHOP",
            .{
                .x = mod_rect.x,
                .y = mod_rect.y - menu_text_height - margin,
            },
            menu_text_height,
            0,
            rl.WHITE,
        );
        rl.DrawTextEx(
            window.font,
            "INCLUDE",
            .{
                .x = mod_rect.x + buy_btn_width,
                .y = mod_rect.y - menu_text_height - margin,
            },
            menu_text_height,
            0,
            rl.WHITE,
        );
        const prev_size = rl.GuiGetStyle(rl.DEFAULT, rl.TEXT_SIZE);
        rl.GuiSetStyle(rl.DEFAULT, rl.TEXT_SIZE, 10);
        for (0..Module.count) |i| {
            self.drawModule(&mod_rect, @truncate(i));
        }
        rl.GuiSetStyle(rl.DEFAULT, rl.TEXT_SIZE, prev_size);
        const zero_day_present = self.modules[@intFromEnum(Module.ZeroDay)];
        const is_player = target_info.s_dev.kind == .Player;
        const can_hack_player = zero_day_present and self.modules[@intFromEnum(Module.Rat)];
        if (self.list_active_index == 0 or (is_player and can_hack_player) or (!is_player and (target_info.access_lvl == .Control or zero_day_present))) {
            const show_dist_btn = std.mem.containsAtLeastScalar(
                bool,
                &self.modules,
                1,
                true,
            );
            if (show_dist_btn and rl.GuiButton(.{
                .x = rect.width + margin,
                .y = window.height - margin - btn_height,
                .height = btn_height,
                .width = rect.width,
            }, "Distribute") == 1) blk: {
                const ip = target_info.s_dev.ip;
                if (self.list_active_index != 0 and target_info.s_dev.kind == .Player) {
                    game.cpl_queue.enqueueWait(.{
                        .Rozryv = .{
                            .target_ip = ip,
                        },
                    });
                    break :blk;
                }
                var curr_buff_i: usize = 0;
                for (self.modules, 0..) |v, i| {
                    if (v) {
                        self.active_modules_ser_buf[curr_buff_i] = @enumFromInt(i);
                        curr_buff_i += 1;
                    }
                }
                game.cpl_queue.enqueueWait(.{
                    .CreateVirus = .{
                        .virus = .{
                            .origin_ip = ip,
                            .modules = self.active_modules_ser_buf[0..curr_buff_i],
                        },
                    },
                });
            }
        }
    }
    onDraw(self) catch |e| {
        std.log.debug("onDraw err: {any}", .{e});
        std.log.debug("{any}", .{@errorReturnTrace()});
    };
}

const buy_btn_width = 200;

fn drawModule(self: *HackGameState, rect: *rl.Rectangle, mod: u8) void {
    std.debug.assert(mod < Module.count);
    const upgrade_btn_rec: rl.Rectangle = .{
        .x = rect.x,
        .y = rect.y,
        .height = rect.height,
        .width = buy_btn_width,
    };
    const module_price = game.player.module_prices[mod];
    if (module_price <= game.player.money_amount) {
        if (rl.GuiButton(upgrade_btn_rec, &self.upgrade_text[mod]) == 1) {
            game.player.money_amount -= module_price;
            self.modules_available[mod] = true;
            game.cpl_queue.enqueueWait(.{
                .UpgradeModule = .{
                    .mod = @enumFromInt(mod),
                },
            });
        }
    }
    self.modules[mod] = self.modules[mod] and self.modules_available[mod];
    _ = rl.GuiCheckBox(
        .{
            .x = rect.x + upgrade_btn_rec.width + 10,
            .y = rect.y,
            .height = rect.height,
            .width = rect.height,
        },
        getModuleText(@enumFromInt(mod)),
        &self.modules[mod],
    );
    rect.y += rect.height;
}

fn getModuleText(mod: Module) [:0]const u8 {
    return switch (mod) {
        .Rat => "RAT module",
        .ZeroDay => "Zero day",
        .Obfuscator => "Obfuscator",
        .Worm => "Worm module",
        .Scout => "Beacon module",
        .Stealer => "Stealer module",
        .Rootkit => "Rootkit module",
    };
}

fn onDraw(self: *HackGameState) !void {
    _ = &self;
    while (game.spl_queue.dequeue()) |spl| {
        switch (spl) {
            .Error => |err| {
                std.log.debug("Server sent error: {any}", .{err});
                const msg = if (err == .IllegalSuharyk) "Kicked for cheating" else "Server returned an error";
                game.changeState(try MsgState.init(msg));
                game.disconnect();
            },
            .BroadcastLeave => {
                // Who cares?
            },
            .Victory => {
                game.changeState(try MsgState.init("You won!"));
                game.disconnect();
            },
            .GameOver => {
                game.changeState(try MsgState.init("You lost :'("));
                game.disconnect();
            },
            .UpdateMoney => |update| {
                game.player.money_amount = update.new_amount;
                self.updateMoneyText();
            },
            .GameStarted,
            .BroadcastJoin,
            => {
                std.log.debug("Game started but got {s}???", .{@tagName(spl)});
            },
            .UpdateModuleCost => |update| {
                game.player.module_prices = update.module_cost;
                for (&self.upgrade_text, 0..) |*text, i| {
                    text.* = @splat(0);
                    _ = std.fmt.bufPrintZ(text, "BUY ({d})", .{update.module_cost[i]}) catch |e| {
                        std.log.debug("Failed to print upgrade text: {any}", .{e});
                        return;
                    };
                }
            },
            .UpdateConnections => |update| {
                {
                    const di = DeviceInfo.init(update.dev, .Control);
                    var res = try game.player.controlled_ips.getOrPut(
                        game.allocator,
                        update.dev.ip,
                    );
                    if (res.found_existing) {
                        res.value_ptr.access_lvl = .Control;
                    } else {
                        res.value_ptr.* = di;
                        try self.addNewIp(di.s_dev.ip);
                    }
                }
                for (update.connections) |dev| {
                    const di = DeviceInfo.init(dev, .View);
                    const res = try game.player.controlled_ips.getOrPut(
                        game.allocator,
                        dev.ip,
                    );
                    if (!res.found_existing) {
                        res.value_ptr.* = di;
                        try self.addNewIp(di.s_dev.ip);
                    }
                }
            },
        }
    }
}

const ip_str_size = 15;

pub fn addNewIp(self: *HackGameState, ip: u32) !void {
    const ip_union: extern union { int: u32, octets: [4]u8 } = .{
        .int = ip,
    };
    const octets = ip_union.octets;
    const str: []u8 = try allocator.alloc(u8, ip_str_size);
    for (str) |*c| c.* = 0;
    _ = try std.fmt.bufPrint(
        str,
        "{d}.{d}.{d}.{d}",
        .{ octets[0], octets[1], octets[2], octets[3] },
    );
    try self.ip_list.append(game.allocator, str.ptr);
}

fn updateMoneyText(self: *HackGameState) void {
    _ = std.fmt.bufPrintZ(
        &self.money_text,
        "{d} $",
        .{game.player.money_amount},
    ) catch |e| {
        std.log.debug("Err while printing money_amount: {any}", .{e});
    };
}

pub fn init() std.mem.Allocator.Error!GameState {
    const gs = try GameState.init(HackGameState);
    var state: *HackGameState = @ptrCast(@alignCast(gs.ctx));
    state.updateMoneyText();
    return gs;
}

pub fn deinit(ctx: *anyopaque) void {
    var self: *HackGameState = @ptrCast(@alignCast(ctx));
    for (self.ip_list.items) |ip_str| game.allocator.free(ip_str[0..ip_str_size]);
    self.ip_list.deinit(game.allocator);
    game.player.controlled_ips.deinit(game.allocator);
}
