const std = @import("std");

/// Reader that throws error.NoUpdates while trying to read empty (but not closed) stream.
/// Detects closed connection by peer
pub const NetStreamReader = struct {
    stream: std.net.Stream,

    const Self = @This();
    pub const Error = std.net.Stream.ReadError || error{NoUpdates};

    pub inline fn read(self: *Self, buf: []u8) Error!usize {
        const bytes_read = try self.stream.read(buf);
        if (bytes_read == 0) {
            return Error.NoUpdates;
        }
        return bytes_read;
    }
};
