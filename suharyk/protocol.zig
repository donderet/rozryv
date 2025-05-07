const std = @import("std");

pub const packet = @import("packet.zig");
pub const net = @import("net.zig");
pub const SyncCircularQueue = @import("SyncCircularQueue.zig");

pub const version: u8 = 0;

pub const client_hello = struct {
    prot_ver: @TypeOf(version),
    name: []u8,
};

pub const server_hello = struct {
    ok: bool,
    members: ?[][]u8,
};

pub const entities = @import("entities.zig");

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
    pub const Reader = std.io.BufferedReader(4096, net.NetStreamReader);
    pub const Writer = std.io.BufferedWriter(4096, std.net.Stream.Writer);

    allocator: std.mem.Allocator,
    bw: Writer,
    br: Reader,

    pub fn init(
        stream: std.net.Stream,
        allocator: std.mem.Allocator,
    ) Duplex {
        return .{
            .allocator = allocator,
            .bw = std.io.bufferedWriter(stream.writer()),
            .br = std.io.bufferedReader(net.NetStreamReader{
                .stream = stream,
            }),
        };
    }

    pub fn deinit(duplex: *Duplex) void {
        duplex.br.unbuffered_reader.stream.close();
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
        var writer = duplex.bw.writer();
        const obj_t = @TypeOf(obj);
        switch (@typeInfo(obj_t)) {
            .@"union" => |u| {
                const tag_type = u.tag_type orelse
                    @compileError(std.fmt.comptimePrint(
                        "Union {s} isn't tagged.",
                        .{@typeName(obj_t)},
                    ));
                const active_tag = std.meta.activeTag(obj);
                try duplex.send(@intFromEnum(obj));
                inline for (std.meta.fields(obj_t)) |f| {
                    if (@field(tag_type, f.name) == active_tag) {
                        try duplex.send(@as(f.type, @field(obj, f.name)));
                    }
                }
            },
            .@"struct" => |s| {
                inline for (s.fields) |f|
                    try send(
                        duplex,
                        @field(obj, f.name),
                    );
            },
            .int => try writer.writeInt(
                std.math.ByteAlignedInt(@TypeOf(obj)),
                @intCast(obj),
                .little,
            ),
            .@"enum" => try send(
                duplex,
                @intFromEnum(obj),
            ),
            .bool => try writer.writeByte(@intFromBool(obj)),
            .array => try writer.writeAll(@ptrCast(&obj)),
            .pointer => |p| switch (p.size) {
                .one => try send(
                    duplex,
                    obj.*,
                ),
                .slice => {
                    try send(duplex, obj.len);
                    for (obj) |e| {
                        try send(duplex, e);
                    }
                },
                else => @compileError(std.fmt.comptimePrint(
                    "Unsupported pointer type: {}",
                    .{@TypeOf(obj)},
                )),
            },
            .optional => {
                try duplex.send(obj != null);
                if (obj) |o| {
                    try send(
                        duplex,
                        o,
                    );
                }
            },
            .void => {},
            else => @compileError(std.fmt.comptimePrint(
                "Unsupported type: {any}",
                .{@TypeOf(obj)},
            )),
        }
        std.log.debug(
            "Sending type {any} buf : {d}",
            .{ obj_t, duplex.bw.buf[0..duplex.bw.end] },
        );
        try duplex.bw.flush();
    }

    /// Recieve packet to obj
    /// obj must be a pointer to an object
    /// Caller must free the recieved object using freePacket
    pub fn recieve(
        duplex: *Duplex,
        obj: anytype,
    ) !void {
        var reader = duplex.br.reader();
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
                obj.* = @intCast(try reader.readInt(deref_t, .little));
            },
            .@"enum" => |e| {
                const int_t = getEnumTagType(e);
                var tag_t_int: int_t = undefined;
                try duplex.recieve(
                    @as(*int_t, &tag_t_int),
                );
                std.log.debug("Recieved tag {d} for type {any}", .{ tag_t_int, int_t });
                obj.* = @enumFromInt(tag_t_int);
            },
            .bool => obj.* = try reader.readByte() == 1,
            .array => {
                for (obj) |*it| {
                    try duplex.recieve(it);
                }
            },
            .pointer => |p| switch (p.size) {
                .slice => {
                    const len = try reader.readInt(usize, .little);
                    obj.* = try duplex.allocator.alloc(p.child, len);
                    errdefer duplex.allocator.free(obj.*);
                    switch (@typeInfo(p.child)) {
                        .int => {
                            _ = try reader.readAll(@ptrCast(obj.*));
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
            .optional => |opt| {
                var not_null: bool = undefined;
                try duplex.recieve(&not_null);
                if (not_null) {
                    var contents: opt.child = undefined;
                    try duplex.recieve(&contents);
                    obj.* = contents;
                } else {
                    obj.* = null;
                }
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
            std.math.log2_int_ceil(u16, e.fields.len),
        ));
    } else {
        int_t = std.math.ByteAlignedInt(e.tag_type);
    }
    return int_t;
}
