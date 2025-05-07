const entities = @import("entities.zig");
const prot = @import("protocol.zig");

pub const ServerPayload = union(enum(u8)) {
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
        ip: u32,
        connections: []entities.Device,
    },
    UpdateMoney: struct {
        new_amount: u64,
    },
    UpdateModuleCost: struct {
        module_cost: [entities.Virus.module_enum_size]u16,
    },
    GameOver: void,
    Victory: void,
};

pub const ClientPayload = union(enum(u8)) {
    Leave: void,
    CreateVirus: struct {
        virus: entities.Virus,
    },
    UpdgradeModule: struct {
        mod: entities.Virus.Module,
    },
    Rozryv: struct {
        target_ip: u32,
    },
};
