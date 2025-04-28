const std = @import("std");
pub const Duplex = @This();
const suharyk = @import("suharyk");
const ServerPayload = suharyk.packet.ServerPayload;
const ClientPayload = suharyk.packet.ClientPayload;

// Decorator pattern
suharyk_duplex: suharyk.Duplex,

pub fn init(server_duplex: suharyk.Duplex) Duplex {
    return .{
        .suharyk_duplex = server_duplex,
    };
}

pub inline fn send(self: *Duplex, pl: ServerPayload) !void {
    self.suharyk_duplex.send(pl) catch |e| {
        // Connection is half-closed, close reading too
        if (e == error.BrokenPipe)
            self.suharyk_duplex.br.unbuffered_reader.stream.close();
        return e;
    };
}

pub inline fn recieve(self: *Duplex, pl: *ClientPayload) !void {
    try self.suharyk_duplex.recieve(pl);
}

pub inline fn freePacket(self: *Duplex, p: ClientPayload) void {
    self.suharyk_duplex.freePacket(p);
}
