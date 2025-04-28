const std = @import("std");
const suharyk = @import("suharyk");
const SuharykDevice = suharyk.entities.Device;
const Device = @This();

// Decorator pattern
suh_entity: *SuharykDevice,
connections: std.ArrayListUnmanaged(SuharykDevice),

pub fn commitConnections(device: *Device) void {
    device.suh_entity.connections = device.connections.items;
}
