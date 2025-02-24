const prot = @import("protocol.zig");

pub const req_join = struct {
    prot_ver: @TypeOf(prot.VERSION),
    name: []u8,
};

pub const resp_join = struct {
    ok: bool,
    members: ?[][]u8,
};

pub const sa_broadcast_join = struct {
    action: prot.ServerAction = .BroadcastJoin,
    name: []u8,
};
