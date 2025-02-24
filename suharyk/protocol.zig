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
    // We don't support big-endian
    std.debug.assert(
        @import("builtin").cpu.arch.endian() == .little,
    );
}

pub const Suharyk = struct {
    pub fn serialize(
        obj: anytype,
        writer: std.net.Stream.Writer,
    ) !void {
        const type_info = @typeInfo(@TypeOf(obj));
        switch (@typeInfo(type_info)) {
            .Struct => |s| {
                inline for (s.fields) |f|
                    try serialize(
                        @field(type_info, f.name),
                        writer,
                    );
            },
            .Int => try writer.writeInt(
                @TypeOf(obj),
                @intCast(obj),
                .little,
            ),
            .Enum => try serialize(
                @intFromEnum(obj),
                writer,
            ),
            .Bool => try writer.writeByte(@intFromBool(obj)),
            .Array => try writer.writeAll(@ptrCast(&obj)),
            .Pointer => |p| switch (p.size) {
                .One => try serialize(
                    obj.*,
                    writer,
                ),
                .Slice => {
                    try serialize(writer, obj.len);
                    try writer.writeAll(@ptrCast(obj));
                },
                else => @compileError(std.fmt.comptimePrint(
                    "Unsupported pointer type: {}",
                    .{@TypeOf(obj)},
                )),
            },
            .Optional => if (obj) {
                try serialize(
                    obj,
                    writer,
                );
            },
            else => @compileError(std.fmt.comptimePrint("Unsupported type: {}", .{@TypeOf(obj)})),
        }
    }

    pub fn deserialize(
        obj: anytype,
        reader: std.net.Stream.Reader,
    ) !void {
        const deref_t = @TypeOf(obj.*);
        const type_info = @typeInfo(deref_t);
        return switch (type_info) {
            .Struct => |s| {
                inline for (s.fields) |f| {
                    const field_ti = @typeInfo(f.type);
                    if (field_ti == .Pointer and field_ti.Pointer.size == .One) {
                        try deserialize(@field(obj.*, f.name), reader);
                    } else {
                        try deserialize(&@field(obj.*, f.name), reader);
                    }
                }
            },
            .Int => obj.* = @intCast(try reader.readInt(deref_t, .little)),
            .Enum => |e| obj.* = @enumFromInt(try deserialize(@as(e.tag_type, obj.*), reader)),
            .Bool => obj.* = try reader.readByte() == 1,
            .Array => {
                try reader.readNoEof(obj);
            },
            .Pointer => |p| switch (p.size) {
                .Slice => {},
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
