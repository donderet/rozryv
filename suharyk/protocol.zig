const std = @import("std");

pub const params = @import("action_params.zig");

pub const VERSION: u8 = 0;

pub const ClientAction = enum {
    Leave,
};

pub const ServerAction = enum {
    // TODO
    BroadcastJoin,
};

pub const Error = enum {
    InvalidRequest,
    ProtocolVersionMismatch,
};

comptime {
    // Only 64-bit LE architectures are supported
    std.debug.assert(
        @import("builtin").cpu.arch.endian() == .little,
    );
    std.debug.assert(
        @sizeOf(usize) == 8,
    );
}

pub const Bridge = struct {
    allocator: std.mem.Allocator,
    bw: std.io.BufferedWriter(4096, std.net.Stream.Writer),
    br: std.io.BufferedReader(4096, std.net.Stream.Reader),

    pub fn init(
        connection: std.net.Server.Connection,
        allocator: std.mem.Allocator,
    ) Bridge {
        return .{
            .allocator = allocator,
            .bw = std.io.bufferedWriter(connection.stream.writer()),
            .br = std.io.bufferedReader(connection.stream.reader()),
        };
    }

    pub fn send(
        bridge: *Bridge,
        obj: anytype,
    ) !void {
        const obj_t = @TypeOf(obj);
        switch (@typeInfo(obj_t)) {
            .Struct => |s| {
                inline for (s.fields) |f|
                    try send(
                        bridge,
                        @field(obj, f.name),
                    );
            },
            .Int => try bridge.bw.writer().writeInt(
                @TypeOf(obj),
                @intCast(obj),
                .little,
            ),
            .Enum => try send(
                bridge,
                @intFromEnum(obj),
            ),
            .Bool => try bridge.bw.writer().writeByte(@intFromBool(obj)),
            .Array => try bridge.bw.writer().writeAll(@ptrCast(&obj)),
            .Pointer => |p| switch (p.size) {
                .One => try send(
                    bridge,
                    obj.*,
                ),
                .Slice => {
                    try send(bridge, obj.len);
                    switch (@typeInfo(p.child)) {
                        .Int => {
                            try bridge.bw.writer().writeAll(@ptrCast(obj));
                        },
                        else => {
                            for (obj) |e| {
                                try send(bridge, e);
                            }
                        },
                    }
                },
                else => @compileError(std.fmt.comptimePrint(
                    "Unsupported pointer type: {}",
                    .{@TypeOf(obj)},
                )),
            },
            .Optional => if (obj) |o| {
                try send(
                    bridge,
                    o,
                );
            },
            else => @compileError(std.fmt.comptimePrint("Unsupported type: {}", .{@TypeOf(obj)})),
        }
        try bridge.bw.flush();
    }

    pub fn recieve(
        bridge: *Bridge,
        obj: anytype,
    ) !void {
        const obj_ti = @typeInfo(@TypeOf(obj));
        if (obj_ti != .Pointer or obj_ti.Pointer.size != .One) {
            @compileError(std.fmt.comptimePrint(
                "Expected pointer to object, got {}",
                .{@TypeOf(obj)},
            ));
        }

        const deref_t = @TypeOf(obj.*);
        const type_info = @typeInfo(deref_t);
        return switch (type_info) {
            .Struct => |s| {
                inline for (s.fields) |f| {
                    const field_ti = @typeInfo(f.type);
                    if (field_ti == .Pointer and field_ti.Pointer.size == .One) {
                        try recieve(bridge, @field(obj.*, f.name));
                    } else {
                        try recieve(bridge, &@field(obj.*, f.name));
                    }
                }
            },
            .Int => {
                obj.* = @intCast(try bridge.br.reader().readInt(deref_t, .little));
            },
            .Enum => |e| obj.* = @enumFromInt(try recieve(
                bridge,
                @as(e.tag_type, obj.*),
            )),
            .Bool => obj.* = try bridge.br.readByte() == 1,
            .Array => {
                try bridge.br.readNoEof(obj);
            },
            .Pointer => |p| switch (p.size) {
                .Slice => {
                    const len = try bridge.br.reader().readInt(usize, .little);
                    obj.* = try bridge.allocator.alloc(p.child, len);
                    errdefer bridge.allocator.free(obj.*);
                    switch (@typeInfo(p.child)) {
                        .Int => {
                            _ = try bridge.br.reader().readAll(@ptrCast(obj.*));
                        },
                        else => {
                            for (0..len) |i| {
                                try recieve(bridge, &obj.*[i]);
                            }
                        },
                    }
                },
                .One => unreachable,
                else => @compileError(std.fmt.comptimePrint(
                    "Unsupported pointer type: {}",
                    .{@TypeOf(obj)},
                )),
            },
            else => @compileError(std.fmt.comptimePrint(
                "Unimplemented type: {}",
                .{deref_t},
            )),
        };
    }
};
