const std = @import("std");
const suharyk = @import("suharyk");
const Duplex = @import("Duplex.zig");
const ServerPayload = suharyk.packet.ServerPayload;
const ClientPayload = suharyk.packet.ClientPayload;

const Game = @This();

var gpa = std.heap.GeneralPurposeAllocator(.{}){};
const allocator = gpa.allocator();

var game_thread: ?std.Thread = null;
pub var name_list = std.ArrayList([]u8).init(allocator);

pub const Player = struct {
    id: usize,
    disconnect: bool = false,
    duplex: Duplex,

    is_host: bool = false,
    name: []u8,

    pub fn init(id: usize, name: []const u8, duplex: Duplex) !Player {
        const p: Player = .{
            .id = id,
            .duplex = duplex,
            .name = try allocator.dupe(u8, name),
            .is_host = name_list.items.len == 0,
        };
        try name_list.append(p.name);
        return p;
    }

    pub fn startGame(player: *Player) !void {
        if (game_thread != null) {
            player.duplex.sendPacket(.{
                .Error = .GameAlreadyStarted,
            });
            return;
        }
        if (!player.is_host) {
            player.duplex.send(.{
                .Error = .IllegalSuharyk,
            });
            return;
        }
        game_thread = std.Thread.spawn(
            .{},
            Game.start,
            .{},
        );
    }

    pub fn deinit(player: *Player) void {
        _ = name_list.swapRemove(player.id);
        allocator.free(player.name);
    }
};

fn start() !void {
    std.log.info("Game started", .{});
}
