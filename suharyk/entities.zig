const std = @import("std");

pub const Device = struct {
    kind: Kind,
    ip: u32,

    pub const Kind = enum {
        PersonalComputer,
        Server,
        Player,
        IoTBulBul,
        IoTCamera,
    };
};

pub const Virus = struct {
    fast: bool,
    origin_ip: u32,
    modules: []Module,

    pub const Module = enum(u8) {
        ZeroDay,
        Stealer,
        Scout,
        Rat,
        Worm,
        Rootkit,
        Obfuscator,
        pub const count = @typeInfo(Module).@"enum".fields.len;
    };
};
