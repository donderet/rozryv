const std = @import("std");
const suharyk = @import("suharyk");
const SuharykDevice = suharyk.entities.Device;
const Device = @This();

// Wrapper pattern
suh_entity: *SuharykDevice,
connection_list: std.ArrayListUnmanaged(SuharykDevice),

pub fn commitConnections(device: *Device) void {
    device.suh_entity.connections = device.connection_list.items;
}
