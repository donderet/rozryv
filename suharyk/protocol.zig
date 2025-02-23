const std = @import("std");

pub const PROTOCOL_VERSION: u8 = 0;

pub const MAX_PACKET_LEN = std.math.maxInt(u16);

pub const Action = enum(u8) {
    Join,
    Leave,
};
