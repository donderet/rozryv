const std = @import("std");

const GameState = @import("GameState.zig");

var gpa: std.heap.DebugAllocator(.{}) = .init;
pub const allocator = gpa.allocator();
pub var state: GameState = undefined;
