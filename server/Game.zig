const std = @import("std");

const Game = @This();

allocator: std.mem.Allocator,

player_count: u8 = 0,
started: bool = false,

pub fn init(a: std.mem.Allocator) Game {
    return .{
        .allocator = a,
    };
}
