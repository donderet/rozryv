const std = @import("std");

/// Reader that throws error.NoUpdates while trying to read empty (but not closed) stream.
/// Detects closed connection by peer
pub const NetStreamReader = struct {
    stream: std.net.Stream,
    closed: bool = false,

    const Self = @This();
    pub const Error = std.net.Stream.ReadError || error{NoUpdates};

    pub inline fn read(self: *Self, buf: []u8) Error!usize {
        const bytes_read = self.stream.read(buf) catch |e| switch (e) {
            error.WouldBlock => return Error.NoUpdates,
            else => return e,
        };
        if (bytes_read == 0) {
            return Error.NoUpdates;
        }
        return bytes_read;
    }

    pub fn close(self: *Self) void {
        if (self.closed) return;
        self.closed = true;
        self.stream.close();
    }
};

pub fn setKeepalive(handle: std.posix.socket_t) !void {
    const timeout = std.posix.timeval{
        .sec = 3,
        .usec = 0,
    };
    try std.posix.setsockopt(
        handle,
        std.posix.SOL.SOCKET,
        std.posix.SO.RCVTIMEO,
        std.mem.asBytes(&timeout),
    );

    try std.posix.setsockopt(
        handle,
        std.posix.SOL.SOCKET,
        std.posix.SO.KEEPALIVE,
        &std.mem.toBytes(@as(c_int, 1)),
    );
    const idle_sec = 5;
    const intvl_sec = 1;
    if (@import("builtin").os.tag == .windows) {
        var keepalive_vals: std.os.windows.mst = extern struct {
            onoff: u32 = 1,
            keepalivetime: u32 = idle_sec * 1000,
            keepaliveinterval: u32 = intvl_sec * 1000,
        };

        const SIO_KEEPALIVE_VALS: u32 = 2550136836;

        const bytes_returned: std.os.windows.DWORD = undefined;
        const result = std.os.windows.WSAIoctl(
            handle,
            SIO_KEEPALIVE_VALS,
            @ptrCast(&keepalive_vals),
            @sizeOf(keepalive_vals),
            null,
            0,
            &bytes_returned,
            null,
            null,
        );
        if (result != 0) {
            const e = std.os.windows.ws2_32.WSAGetLastError();
            std.log.err(
                "Failed to set keepalive options with error {d}",
                .{e},
            );
            return error.WSAIoctlErr;
        }
    } else {
        try std.posix.setsockopt(
            handle,
            std.posix.IPPROTO.TCP,
            std.posix.TCP.KEEPIDLE,
            &std.mem.toBytes(@as(c_int, idle_sec)),
        );
        try std.posix.setsockopt(
            handle,
            std.posix.IPPROTO.TCP,
            std.posix.TCP.KEEPINTVL,
            &std.mem.toBytes(@as(c_int, intvl_sec)),
        );
        try std.posix.setsockopt(
            handle,
            std.posix.IPPROTO.TCP,
            std.posix.TCP.KEEPCNT,
            &std.mem.toBytes(@as(c_int, 3)),
        );
    }
}
