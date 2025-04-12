const std = @import("std");

pub const Device = struct {
    kind: Kind,
    ip: u32,
    connections: []Device,

    pub const Kind = enum {
        PersonalComputer,
        Server,
        Player,
        IoTBulBul,
        IoTCamera,
        IoTBoiler,
        IoTAirConditioner,
    };
};
