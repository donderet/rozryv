const std = @import("std");

const suharyk = @import("suharyk");
const Module = suharyk.entities.Virus.Module;
const SuharykDevice = suharyk.entities.Device;

const game = @import("game.zig");

const Player = @This();

const AccessLevel = enum {
    View,
    Control,
};

pub const DeviceInfo = struct {
    s_dev: SuharykDevice,
    access_lvl: AccessLevel,
    desc: [:0]const u8,

    pub fn init(s_dev: SuharykDevice, access_lvl: AccessLevel) DeviceInfo {
        var di: DeviceInfo = .{
            .s_dev = s_dev,
            .access_lvl = access_lvl,
            .desc = undefined,
        };
        const is_game_player = game.player.controlled_ips.count() == 0;
        di.desc = switch (s_dev.kind) {
            .Player => if (is_game_player) "This is your PC, a great starting point." else "Another player! Time for some fun! >:)",
            .Server => "Some server.",
            .PersonalComputer => "A very lovely personal computer. I don't need it though, I have my own.",
            .IoTBulBul => "Blup-blup, this is a water dispenser. Who would have thought it is a good idea to control it using Wi-Fi?",
            .IoTCamera => "A classic model of IP-camera.",
        };
        return di;
    }
};

is_host: bool = false,
money_amount: u64 = 0,
module_prices: [Module.count]u64 = @splat(std.math.maxInt(u64)),
upgrade_prices: [Module.count]u64 = @splat(std.math.maxInt(u64)),
controlled_ips: std.AutoArrayHashMapUnmanaged(u32, DeviceInfo) = .empty,
