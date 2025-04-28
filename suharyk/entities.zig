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

pub const Virus = struct {
    fast: bool,
    modules: struct {
        zero_day: bool,
        stealer: bool,
        scout: bool,
        rat: bool,
        worm: bool,
        rootkit: bool,
        obfuscator: bool,
    },
};
