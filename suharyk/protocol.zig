const std = @import("std");

pub const packet = @import("packet.zig");

pub const VERSION: u8 = 0;

pub const client_hello = struct {
    prot_ver: @TypeOf(VERSION),
    name: []u8,
};

pub const server_hello = struct {
    ok: bool,
    members: ?[][]u8,
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
            .Union => |u| {
                const tag_type = u.tag_type orelse
                    @compileError(std.fmt.comptimePrint(
                    "Union {s} isn't tagged.",
                    .{@typeName(obj_t)},
                ));
                try bridge.send(@intFromEnum(obj));
                try bridge.send(@as(tag_type, obj));
            },
            .Struct => |s| {
                inline for (s.fields) |f|
                    try send(
                        bridge,
                        @field(obj, f.name),
                    );
            },
            .Int => try bridge.bw.writer().writeInt(
                std.math.ByteAlignedInt(@TypeOf(obj)),
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
        if (obj_ti.Pointer.is_const) {
            @compileError(std.fmt.comptimePrint(
                "Cannot recieve to a const pointer {any}. ",
                .{@TypeOf(obj)},
            ));
        }

        const deref_t = @TypeOf(obj.*);
        const type_info = @typeInfo(deref_t);
        switch (type_info) {
            .Union => |u| u_blk: {
                const tag_type = u.tag_type orelse
                    @compileError(std.fmt.comptimePrint(
                    "Union {s} isn't tagged.",
                    .{@typeName(deref_t)},
                ));
                var tag_id: tag_type = undefined;
                try bridge.recieve(&tag_id);
                inline for (std.meta.fields(deref_t)) |f| {
                    if (@field(tag_type, f.name) == tag_id) {
                        var val: f.type = undefined;
                        try bridge.recieve(@as(
                            *f.type,
                            &val,
                        ));
                        obj.* = @unionInit(deref_t, f.name, val);
                        break :u_blk;
                    }
                }
            },
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
            .Enum => |e| {
                const int_t = getEnumTagType(e);
                var tag_t_int: int_t = undefined;
                try bridge.recieve(
                    @as(*int_t, &tag_t_int),
                );
                obj.* = @enumFromInt(tag_t_int);
            },
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
            .Void => {},
            else => @compileError(std.fmt.comptimePrint(
                "Unimplemented type: {}",
                .{deref_t},
            )),
        }
    }
};

fn getEnumTagType(e: std.builtin.Type.Enum) type {
    comptime var int_t: type = undefined;
    if (e.is_exhaustive) {
        int_t = std.math.ByteAlignedInt(std.meta.Int(
            .unsigned,
            e.fields.len,
        ));
    } else {
        int_t = std.math.ByteAlignedInt(e.tag_type);
    }
    return int_t;
}
