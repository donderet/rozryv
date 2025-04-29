const std = @import("std");

const suharyk = @import("suharyk");
const SuharykVirus = suharyk.entities.Virus;

const Game = @import("../Game.zig");
const Device = @import("Device.zig");
const Player = @import("Player.zig");
const RandomTickable = @import("RandomTickable.zig");
const VBoard = @import("VBoard.zig");

const Virus = @This();

owner: *Player,
fast: bool,
origin_ip: u32,
modules: struct {
    zero_day: bool = false,
    stealer: bool = false,
    scout: bool = false,
    rat: bool = false,
    worm: bool = false,
    rootkit: bool = false,
    obfuscator: bool = false,
},
target_index: usize,

heap_ptr: ?*Virus = null,

pub fn init(owner: *Player, suh_virus: SuharykVirus) Virus {
    var v: Virus = .{
        .owner = owner,
        .suh_virus = suh_virus,
        .index = Game.ipToIndex(suh_virus.origin_ip),
        .fast = suh_virus.fast,
        .origin_ip = suh_virus.origin_ip,
        .modules = .{},
    };
    for (suh_virus.modules) |mod| {
        switch (mod) {
            .Stealer => v.modules.stealer = true,
            .Worm => v.modules.worm = true,
            .Rat => v.modules.rat = true,
            .Obfuscator => v.modules.obfuscator = true,
            .Scout => v.modules.scout = true,
            .ZeroDay => v.modules.zero_day = true,
            .Rootkit => v.modules.rootkit = true,
        }
    }
    return v;
}

inline fn getRndInterval(self: Virus) u16 {
    if (self.suh_virus.fast)
        return 1
    else
        return 2;
}

pub fn randomTickable(self: *Virus) RandomTickable {
    return .{
        .ctx = self,
        .vtable = .{
            .interval = self.getRndInterval(),
            .onRandomTick = &onRandomTick,
            .deinit = deinit,
        },
    };
}

pub fn deinit(self: Virus) void {
    if (self.heap_ptr) |ptr| {
        Game.allocator.destroy(ptr);
    }
}

fn onRandomTick(self: *Virus) bool {
    const dev: *Device = Game.vboard.devices[self.target_index];
    const ip = self.getNotInfectedIp(self.target_index) catch {
        return;
    };
    var should_update_cons = false;
    if (self.modules.rat) {
        self.owner.controlled_ips.put(Game.allocator, ip, .Control) catch |e| {
            std.log.debug("Failed to add to controlled ips: {any}", .{e});
        };
        should_update_cons = true;
    }
    if (self.modules.stealer) {
        self.owner.addMoney(10);
    }
    if (self.modules.worm) blk: {
        const next_ip = self.getNotInfectedIp(self.index) catch break :blk;
        var copy: *Virus = Game.allocator.create(Virus) catch break :blk;
        copy.* = self.*;
        copy.heap_ptr = copy;
        copy.origin_ip = next_ip;
        self.append(Game.allocator, copy.randomTickable().asTickable());
    }
    if (self.modules.rootkit) {
        self.owner.controlled_ips.put(Game.allocator, ip, .PermanentControl) catch |e| {
            std.log.debug("Failed to add to permanently controlled ips: {any}", .{e});
        };
        should_update_cons = true;
    }
    if (should_update_cons) {
        for (dev.connections.items) |d| {
            self.owner.controlled_ips.put(Game.allocator, d.ip, .View);
        }
        self.owner.server_req_queue.enqueueWait(.{
            .UpdateConnections = .{
                .ip = self.origin_ip,
                .connections = dev.connections.items,
            },
        });
    }
}

fn getNotInfectedIp(self: Virus, infected_i: usize) error{NoIpAvailable}!u32 {
    var target_i = VBoard.getRndPointAround(
        infected_i / VBoard.v_map_side,
        infected_i % VBoard.v_map_side,
        4,
    );
    for (0..32) |_| {
        const ip = Game.vboard.devices[target_i].suh_entity.ip;
        const is_player = false;
        for (Game.players.items) |player| {
            if (ip == player.device.suh_entity.ip) {
                is_player = true;
                break;
            }
        }
        if (!is_player and !self.owner.controlled_ips.contains(
            ip,
        )) return target_i;
        target_i = VBoard.getRndPointAround(
            target_i / VBoard.v_map_side,
            target_i % VBoard.v_map_side,
            4,
        );
    }
    return error.NoIpAvailable;
}
