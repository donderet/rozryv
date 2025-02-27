const std = @import("std");
pub const Duplex = @This();
const suharyk = @import("suharyk");
const ServerPayload = suharyk.packet.ServerPayload;
const ClientPayload = suharyk.packet.ClientPayload;

suharyk_duplex: suharyk.Duplex,

pub fn init(server_duplex: suharyk.Duplex) Duplex {
    return .{
        .suharyk_duplex = server_duplex,
    };
}

pub inline fn send(self: *Duplex, pl: ServerPayload) !void {
    try self.suharyk_duplex.send(pl);
}

pub inline fn recieve(self: *Duplex, pl: *ClientPayload) !void {
    try self.suharyk_duplex.recieve(pl);
}

pub inline fn freePacket(self: *Duplex, p: ClientPayload) void {
    self.suharyk_duplex.freePacket(p);
}
