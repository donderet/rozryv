const prot = @import("protocol.zig");

pub const ServerPayload = union(enum) {
    BroadcastJoin: struct {
        name: []u8,
    },
    BroadcastLeave: struct {
        name: []u8,
    },
};

pub const ClientPayload = union(enum) {
    Leave: void,
};
