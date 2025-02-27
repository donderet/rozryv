const prot = @import("protocol.zig");

pub const ServerPayload = union(enum) {
    Error: enum {
        IllegalSuharyk,
        GameAlreadyStarted,
    },
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
