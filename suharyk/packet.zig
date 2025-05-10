const entities = @import("entities.zig");
const prot = @import("protocol.zig");

// Command pattern
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
        dev: entities.Device,
        connections: []entities.Device,
    },
    UpdateMoney: struct {
        new_amount: u64,
    },
    UpdateModuleCost: struct {
        module_cost: [entities.Virus.Module.count]u64,
    },
    GameOver: void,
    Victory: void,
};

pub const ClientPayload = union(enum) {
    Leave: void,
    StartGame: void,
    CreateVirus: struct {
        virus: entities.Virus,
    },
    UpgradeModule: struct {
        mod: entities.Virus.Module,
    },
    Rozryv: struct {
        target_ip: u32,
    },
};
