const std = @import("std");

const suharyk = @import("suharyk");
const SuharykDevice = suharyk.entities.Device;

const Device = @This();

suh_entity: SuharykDevice,
connections: std.ArrayListUnmanaged(SuharykDevice),
