const std = @import("std");
const ClientHandler = @import("ClientHandler.zig");

const Game = @This();

const gpa = std.heap.GeneralPurposeAllocator(.{}){};
const allocator = gpa.allocator();
pub var name_list = std.ArrayList([]u8).init(allocator);

pub const Player = struct {
    handler: ClientHandler,

    name: []u8,

    pub fn init(name: []const u8, handler: ClientHandler) Player {
        const p = .{
            .handler = handler,
            .name = allocator.dupe(u8, name),
        };
        name_list.append(name);
        return p;
    }

    pub fn deinit(player: Player) void {
        _ = name_list.swapRemove(player.handler.id);
        allocator.free(player.name);
    }
};
