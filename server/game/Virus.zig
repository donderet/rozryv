const std = @import("std");

const suharyk = @import("suharyk");
const SuharykVirus = suharyk.entities.Virus;
const Moudule = SuharykVirus.Module;

const Game = @import("../Game.zig");
const Device = @import("Device.zig");
const Player = @import("Player.zig");
const RandomTickable = @import("RandomTickable.zig");
const VBoard = @import("VBoard.zig");

const Virus = @This();

owner: *Player,
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
detection_chance: u8,
detection_accumulator: u4 = 0,
target_index: usize,

heap_ptr: ?*Virus = null,
rnd_tkbl: RandomTickable = undefined,
rnd_tkbl_vt: RandomTickable.VTable = undefined,

pub fn init(owner: *Player, suh_virus: SuharykVirus) Virus {
    const indx = Game.ipToIndex(suh_virus.origin_ip) orelse blk: {
        owner.kickForIllegalPacket();
        break :blk 0;
    };
    var v: Virus = .{
        .owner = owner,
        .target_index = indx,
        .origin_ip = suh_virus.origin_ip,
        .detection_chance = 0,
        .modules = .{},
    };
    for (suh_virus.modules) |mod| {
        owner.use_count_arr[@intFromEnum(mod)] += 1;
        var additional_chance = owner.use_count_arr[@intFromEnum(mod)] * 5;
        if (additional_chance >= 30) additional_chance = 30;
        switch (mod) {
            .Stealer => {
                v.modules.stealer = true;
                v.detection_chance +|= 20;
            },
            .Worm => {
                v.modules.worm = true;
                v.detection_chance +|= 20;
            },
            .Rat => {
                v.modules.rat = true;
                v.detection_chance +|= 30;
            },
            .Obfuscator => {
                v.modules.obfuscator = true;
            },
            .Scout => {
                v.modules.scout = true;
                v.detection_chance +|= 10;
            },
            .ZeroDay => {
                v.modules.zero_day = true;
                v.detection_chance +|= 0;
            },
            .Rootkit => {
                v.modules.rootkit = true;
                v.detection_chance +|= 10;
            },
        }
    }
    if (v.modules.obfuscator) v.detection_chance /= @truncate(
        @max(
            3 - (owner.use_count_arr[@intFromEnum(Moudule.Obfuscator)] / 2),
            1,
        ),
    );
    if (v.detection_chance > 90) v.detection_chance = 90;
    if (v.detection_chance < 5) v.detection_chance = 5;
    return v;
}

pub fn randomTickable(self: *Virus) *RandomTickable {
    self.rnd_tkbl_vt = .{
        .interval = 2,
        .onRandomTick = onRandomTick,
        .deinit = deinit,
    };
    self.rnd_tkbl = .{
        .ctx = self,
        .vtable = &self.rnd_tkbl_vt,
    };
    return &self.rnd_tkbl;
}

pub fn deinit(ctx: *anyopaque) void {
    const self: *Virus = @ptrCast(@alignCast(ctx));
    if (self.heap_ptr) |ptr| {
        Game.allocator.destroy(ptr);
    }
}

fn onRandomTick(ctx: *anyopaque, dead_ptr: *bool) void {
    var self: *Virus = @ptrCast(@alignCast(ctx));
    if (self.detection_accumulator == 10) {
        dead_ptr.* = true;
        return;
    }
    if (Game.prng.uintAtMost(u8, 100) <= self.detection_chance) {
        self.detection_accumulator += 1;
    }
    const dev: *Device = &VBoard.devices[self.target_index];
    const ip = self.getNotInfectedIp(self.target_index) catch {
        dead_ptr.* = true;
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
        const rnd_ceil: u64 = switch (VBoard.devices[Game.ipToIndex(ip).?].suh_entity.kind) {
            .Server => 1000,
            .Player => 100,
            else => 50,
        };
        const addend_amount = Game.prng.uintAtMost(u64, rnd_ceil);
        self.owner.addMoney(addend_amount * (self.owner.upgrades[@intFromEnum(Moudule.Stealer)] + 1));
    }
    if (self.modules.worm) blk: {
        const next_ip = self.getNotInfectedIp(self.target_index) catch break :blk;
        var copy: *Virus = Game.allocator.create(Virus) catch break :blk;
        copy.* = self.*;
        copy.heap_ptr = copy;
        copy.origin_ip = next_ip;
        Game.on_tick.append(Game.allocator, copy.randomTickable().asTickable()) catch |e| {
            std.log.debug("Failed to populate worm: {any}", .{e});
        };
    }
    if (self.modules.rootkit) {
        self.owner.controlled_ips.put(
            Game.allocator,
            ip,
            .PermanentControl,
        ) catch |e| {
            std.log.debug("Failed to add to permanently controlled ips: {any}", .{e});
        };
        should_update_cons = true;
    }
    if (should_update_cons) {
        for (dev.connections.items) |d| {
            self.owner.controlled_ips.put(
                Game.allocator,
                d.ip,
                .View,
            ) catch |e| {
                std.log.debug("Failed to put to controlled_ips: {any}", .{e});
            };
        }
        self.owner.server_req_queue.enqueueWait(.{
            .UpdateConnections = .{
                .dev = dev.suh_entity,
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
        const ip = VBoard.devices[target_i].suh_entity.ip;
        var is_player = false;
        for (Game.players.items) |player| {
            if (ip == player.device.suh_entity.ip) {
                is_player = true;
                break;
            }
        }
        if (!is_player and !self.owner.controlled_ips.contains(
            ip,
        )) return ip;
        target_i = VBoard.getRndPointAround(
            target_i / VBoard.v_map_side,
            target_i % VBoard.v_map_side,
            4,
        );
    }
    return error.NoIpAvailable;
}
