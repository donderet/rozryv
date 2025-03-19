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

/// Handles two-way communication between client and server using Suharyk protocol.
pub const Duplex = struct {
    allocator: std.mem.Allocator,
    bw: std.io.BufferedWriter(4096, std.net.Stream.Writer),
    br: std.io.BufferedReader(4096, std.net.Stream.Reader),

    pub fn init(
        connection: std.net.Server.Connection,
        allocator: std.mem.Allocator,
    ) Duplex {
        return .{
            .allocator = allocator,
            .bw = std.io.bufferedWriter(connection.stream.writer()),
            .br = std.io.bufferedReader(connection.stream.reader()),
        };
    }

    /// Frees recieved packet
    pub fn freePacket(duplex: Duplex, p: anytype) void {
        const p_ti = @typeInfo(@TypeOf(p));
        if (p_ti == .@"union") {
            const active_field = p_ti.@"union".tag_type orelse
                @compileError(std.fmt.comptimePrint(
                    "Union {s} isn't tagged.",
                    .{@typeName(packet)},
                ));
            duplex.freePacket(@as(active_field, p));
        } else if (p_ti == .@"struct") {
            inline for (p_ti.@"struct".fields) |f| {
                duplex.freePacket(@field(p, f.name));
            }
        } else if (p_ti == .pointer and p_ti.pointer.size == .slice) {
            duplex.allocator.free(p);
            return;
        }
    }

    pub fn send(
        duplex: *Duplex,
        obj: anytype,
    ) !void {
        const obj_t = @TypeOf(obj);
        switch (@typeInfo(obj_t)) {
            .@"union" => |u| {
                const tag_type = u.tag_type orelse
                    @compileError(std.fmt.comptimePrint(
                        "Union {s} isn't tagged.",
                        .{@typeName(obj_t)},
                    ));
                try duplex.send(@intFromEnum(obj));
                try duplex.send(@as(tag_type, obj));
            },
            .@"struct" => |s| {
                inline for (s.fields) |f|
                    try send(
                        duplex,
                        @field(obj, f.name),
                    );
            },
            .int => try duplex.bw.writer().writeInt(
                std.math.ByteAlignedInt(@TypeOf(obj)),
                @intCast(obj),
                .little,
            ),
            .@"enum" => try send(
                duplex,
                @intFromEnum(obj),
            ),
            .bool => try duplex.bw.writer().writeByte(@intFromBool(obj)),
            .array => try duplex.bw.writer().writeAll(@ptrCast(&obj)),
            .pointer => |p| switch (p.size) {
                .one => try send(
                    duplex,
                    obj.*,
                ),
                .slice => {
                    try send(duplex, obj.len);
                    switch (@typeInfo(p.child)) {
                        .int => {
                            try duplex.bw.writer().writeAll(@ptrCast(obj));
                        },
                        else => {
                            for (obj) |e| {
                                try send(duplex, e);
                            }
                        },
                    }
                },
                else => @compileError(std.fmt.comptimePrint(
                    "Unsupported pointer type: {}",
                    .{@TypeOf(obj)},
                )),
            },
            .optional => if (obj) |o| {
                try send(
                    duplex,
                    o,
                );
            },
            else => @compileError(std.fmt.comptimePrint("Unsupported type: {}", .{@TypeOf(obj)})),
        }
        try duplex.bw.flush();
    }

    /// Recieve packet to obj
    /// obj must be a pointer to an object
    /// Caller must free the recieved object using freePacket
    pub fn recieve(
        duplex: *Duplex,
        obj: anytype,
    ) !void {
        const obj_ti = @typeInfo(@TypeOf(obj));
        if (obj_ti != .pointer or obj_ti.pointer.size != .one) {
            @compileError(std.fmt.comptimePrint(
                "Expected pointer to object, got {}",
                .{@TypeOf(obj)},
            ));
        }
        if (obj_ti.pointer.is_const) {
            @compileError(std.fmt.comptimePrint(
                "Cannot recieve to a const pointer {any}. ",
                .{@TypeOf(obj)},
            ));
        }

        const deref_t = @TypeOf(obj.*);
        const type_info = @typeInfo(deref_t);
        switch (type_info) {
            .@"union" => |u| u_blk: {
                const tag_type = u.tag_type orelse
                    @compileError(std.fmt.comptimePrint(
                        "Union {s} isn't tagged.",
                        .{@typeName(deref_t)},
                    ));
                var tag_id: tag_type = undefined;
                try duplex.recieve(&tag_id);
                inline for (std.meta.fields(deref_t)) |f| {
                    if (@field(tag_type, f.name) == tag_id) {
                        var val: f.type = undefined;
                        try duplex.recieve(@as(
                            *f.type,
                            &val,
                        ));
                        obj.* = @unionInit(deref_t, f.name, val);
                        break :u_blk;
                    }
                }
            },
            .@"struct" => |s| {
                inline for (s.fields) |f| {
                    const field_ti = @typeInfo(f.type);
                    if (field_ti == .pointer and field_ti.pointer.size == .one) {
                        try recieve(duplex, @field(obj.*, f.name));
                    } else {
                        try recieve(duplex, &@field(obj.*, f.name));
                    }
                }
            },
            .int => {
                obj.* = @intCast(try duplex.br.reader().readInt(deref_t, .little));
            },
            .@"enum" => |e| {
                const int_t = getEnumTagType(e);
                var tag_t_int: int_t = undefined;
                try duplex.recieve(
                    @as(*int_t, &tag_t_int),
                );
                obj.* = @enumFromInt(tag_t_int);
            },
            .bool => obj.* = try duplex.br.readByte() == 1,
            .array => {
                try duplex.br.readNoEof(obj);
            },
            .pointer => |p| switch (p.size) {
                .slice => {
                    const len = try duplex.br.reader().readInt(usize, .little);
                    obj.* = try duplex.allocator.alloc(p.child, len);
                    errdefer duplex.allocator.free(obj.*);
                    switch (@typeInfo(p.child)) {
                        .int => {
                            _ = try duplex.br.reader().readAll(@ptrCast(obj.*));
                        },
                        else => {
                            for (0..len) |i| {
                                try recieve(duplex, &obj.*[i]);
                            }
                        },
                    }
                },
                .one => unreachable,
                else => @compileError(std.fmt.comptimePrint(
                    "Unsupported pointer type: {}",
                    .{@TypeOf(obj)},
                )),
            },
            .void => {},
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
