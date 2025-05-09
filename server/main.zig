const std = @import("std");

const Listener = @import("Listener.zig");

pub fn main() !void {
    var gpa: std.heap.DebugAllocator(.{}) = .init;
    const allocator = gpa.allocator();
    defer _ = gpa.deinit();

    var option_ip: []const u8 = undefined;
    var option_port: []const u8 = undefined;
    var parser = ArgParser.init(allocator);
    defer parser.deinit();
    parser.addArg(
        "-ip",
        &option_ip,
        "127.0.0.1",
    ).addArg(
        "-port",
        &option_port,
        "6000",
    ).parse() catch |e| {
        if (e == error.MissingValue) {
            std.log.err("Missing value for option", .{});
        } else return e;
    };

    const addr = std.net.Address.resolveIp(
        option_ip,
        try std.fmt.parseInt(u16, option_port, 10),
    ) catch |e| {
        std.log.err("Failed to resolve {s}:{s}", .{ option_ip, option_port });
        std.log.debug("{any}", .{e});
        return;
    };

    try Listener.start(addr, allocator);
}

const ArgParser = struct {
    allocator: std.mem.Allocator,
    options_list: std.ArrayListUnmanaged(Option) = .empty,

    const Option = struct {
        is_set: bool = false,
        name: []const u8,
        slice: *[]const u8,
        default: []const u8,

        pub fn getValue(self: Option) []const u8 {
            return if (self.is_set) self.slice.* else self.default;
        }
    };

    pub fn init(allocator: std.mem.Allocator) ArgParser {
        return .{
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *ArgParser) void {
        for (self.options_list.items) |*option| {
            if (option.is_set) {
                self.allocator.free(option.slice.*);
            }
        }
        self.options_list.deinit(self.allocator);
    }

    // Builder pattern
    pub fn addArg(
        self: *ArgParser,
        name: []const u8,
        target_slice: *[]const u8,
        default: []const u8,
    ) *ArgParser {
        self.options_list.append(self.allocator, .{
            .name = name,
            .slice = target_slice,
            .default = default,
        }) catch |e| {
            std.log.debug("Failed to add to options parse list {any}", .{e});
        };
        return self;
    }

    pub fn parse(self: ArgParser) !void {
        var args = try std.process.argsWithAllocator(self.allocator);
        defer args.deinit();
        while (args.next()) |arg| {
            for (self.options_list.items) |*option| {
                if (std.mem.eql(u8, option.name, arg)) {
                    const val = args.next() orelse return error.MissingValue;
                    option.slice.* = try self.allocator.dupe(u8, val);
                    option.is_set = true;
                }
            }
        }
        for (self.options_list.items) |*option| {
            option.slice.* = option.getValue();
        }
    }
};
