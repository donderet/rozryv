const std = @import("std");

const suharyk = @import("suharyk");
const suh_entities = suharyk.entities;
const SuhDevice = suh_entities.Device;

const Game = @import("../Game.zig");
const allocator = Game.allocator;
const Device = @import("Device.zig");
const RandomTickable = @import("RandomTickable.zig");

const VBoard = @This();
const v_map_side = 16;
const devices_count = v_map_side * v_map_side;
const devices: [devices_count]Device = undefined;

pub fn generate() void {
    const pcount = Game.playerCount();

    const rows = @floor(std.math.sqrt(pcount));
    const columns = rows;

    const row_spacing = v_map_side / rows;
    const column_spacing = row_spacing;

    var row: usize = 0;
    var column: usize = 0;

    for (Game.getPlayers().items) |player| {
        var row_margin = row_spacing;
        var column_margin = column_spacing;
        if (row == 0) {
            row_margin /= 2;
        }
        if (column == 0) {
            column_margin /= 2;
        }
        var dev: *Device = &devices[row * v_map_side + column];
        dev.suh_entity = .{
            .kind = .Player,
            .ip = getRndIp(),
            .connection_list = .empty,
        };
        dev.commitConnections();
        player.device = dev;
        column += 1;
        if (column == columns) {
            row += 1;
            column = 0;
        }
    }
    for (devices) |*device| {
        device.suh_entity.ip = getRndIp();
        device.suh_entity.kind = Game.prng.enumValue(SuhDevice.Kind);
    }
    for (0..devices.len) |i| generateConnections(i);
    const rt: RandomTickable = .{ .ctx = undefined, .vtable = .{
        .{
            .interval = 2,
            .onRandomTick = &randomizeConnection,
        },
    } };
    Game.on_tick.append(Game.allocator, rt.asTickable());
}

fn randomizeConnection(_: *anyopaque) void {
    while (true) {
        const rnd_i = Game.prng.uintLessThan(usize, devices);
        if (devices[rnd_i].suh_entity.kind == .Player)
            continue;
        const rnd_dev = devices[rnd_i];
        const disconnect = Game.prng.boolean();
        if (disconnect) {
            const con_i = Game.prng.uintLessThan(usize, rnd_dev.connections.items.len);
            // TODO: notify about removing
            rnd_dev.connections.swapRemove(con_i);
            return;
        }
        generateConnection(rnd_dev, rnd_i);
    }
}

fn getRndIp() u32 {
    // Class-A IP-address (1.0.0.0–126.255.255.255, excluding 10.x.x.x)
    const rnd_ip: union { int: u32, octets: [4]u8 } = Game.prng.int(u32) & 0x7f_ff_ff_ff;
    const first_octet = rnd_ip.octets[0];
    if (first_octet == 127 or first_octet == 10 or first_octet == 0) {
        @branchHint(.cold);
        rnd_ip.octets[0] = 126;
    }
    return rnd_ip.int;
}

fn generateConnections(i: usize) void {
    const device = devices[i];
    if (device.suh_entity.kind == .Player) return;
    const max_connections = getMaxConnections(device.suh_entity.kind);
    defer device.commitConnections();
    for (0..max_connections) |_| {
        generateConnection(i);
    }
}

fn generateConnection(i: usize) void {
    for (0..16) |_| {
        const rnd_point = getRndPointAround(i / v_map_side, i % v_map_side, 4);

        if (isValidConnection(
            devices[i].suh_entity,
            devices[rnd_point].suh_entity,
        ) and !std.mem.containsAtLeast(
            *Device,
            devices[i].connections.items,
            1,
            devices[rnd_point],
        )) {
            devices[i].connections.append(allocator, devices[rnd_point].suh_entity);
            break;
        }
    }
    std.log.debug(
        "Couldn't generate connection for ({d}, {d})",
        .{ i / v_map_side, i % v_map_side, 4 },
    );
}

/// Checks if randomly generated connection is valid
fn isValidConnection(requester: SuhDevice, recipient: SuhDevice) bool {
    std.debug.assert(requester.kind != .Player);
    if (recipient.kind == .Player) return false;
    return switch (requester.kind) {
        .Player => unreachable,
        .Server => true,
        .PersonalComputer => recipient.kind != .PersonalComputer,
        .IoTBulBul, .IoTCamera, .IoTBoiler, .IoTAirConditioner => recipient.kind == .Server,
    };
}

fn getRndPointAround(row: usize, column: usize, range: usize) usize {
    const half_range = (range / 2);
    const rnd_row = Game.prng.intRangeAtMost(
        usize,
        row -| half_range,
        @max(v_map_side, row + half_range),
    );
    const rnd_column = Game.prng.intRangeAtMost(
        usize,
        column -| half_range,
        @max(v_map_side, column + half_range),
    );
    return rnd_row * v_map_side + rnd_column;
}

fn getMaxConnections(kind: SuhDevice.Kind) u8 {
    return switch (kind) {
        .Player => unreachable,
        .Server => 8,
        .PersonalComputer => 2,
        .IoTBulBul, .IoTCamera, .IoTBoiler, .IoTAirConditioner => 2,
    };
}
