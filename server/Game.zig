const std = @import("std");
const ClientHandler = @import("ClientHandler.zig");
const suharyk = @import("suharyk");

const Game = @This();

var gpa = std.heap.GeneralPurposeAllocator(.{}){};
const allocator = gpa.allocator();
pub var name_list = std.ArrayList([]u8).init(allocator);

pub const Player = struct {
    id: usize,
    disconnect: bool,
    suharyk_bridge: suharyk.Bridge,

    name: []u8,

    pub fn init(id: usize, name: []const u8, bridge: suharyk.Bridge) !Player {
        const p = .{
            .id = id,
            .suharyk_bridge = bridge,
            .name = try allocator.dupe(u8, name),
        };
        try name_list.append(p.name);
        return p;
    }

    pub fn deinit(player: Player) void {
        _ = name_list.swapRemove(player.id);
        allocator.free(player.name);
    }
};
