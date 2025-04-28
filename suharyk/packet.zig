const entities = @import("entities.zig");
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
    GameStarted: struct {
        player_ip: u32,
    },
    UpdateConnections: struct {
        device: entities.Device,
    },
};

pub const ClientPayload = union(enum) {
    Leave: void,
    CreateVirus: struct {
        origin_ip: u32,
        virus: entities.Virus,
    },
};
