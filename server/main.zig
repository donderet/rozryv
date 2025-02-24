const std = @import("std");
const Listener = @import("Listener.zig");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();

    const addr = std.net.Address.initIp4(.{ 127, 0, 0, 1 }, 6789);
    try Listener.start(addr, allocator);
}
