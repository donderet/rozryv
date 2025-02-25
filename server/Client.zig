const std = @import("std");
const suharyk_prot = @import("suharyk");
const Game = @import("Game.zig");
const Listener = @import("Listener.zig");

const Client = @This();

id: usize,
connection: std.net.Server.Connection,
allocator: std.mem.Allocator,
player: Game.Player = undefined,

pub fn init(
    con: std.net.Server.Connection,
    a: std.mem.Allocator,
) Client {
    return Client{
        .connection = con,
        .allocator = a,
        .id = Listener.clients.items.len,
    };
}

pub fn handle(client: *Client) !void {
    var suharyk_bridge = suharyk_prot.Bridge.init(client.connection, client.allocator);

    var join_req: suharyk_prot.params.req_join = undefined;
    try suharyk_bridge.recieve(&join_req);
    std.log.debug(
        "{s} joined the game",
        .{ join_req.name, join_req.prot_ver },
    );
    const protocol_matches = join_req.prot_ver == suharyk_prot.VERSION;
    const resp: suharyk_prot.params.resp_join = .{
        .ok = protocol_matches,
        .members = if (protocol_matches) Game.name_list.items else null,
    };
    try suharyk_bridge.send(resp);
    client.player = try Game.Player.init(client.id, join_req.name, suharyk_bridge);
    defer client.player.deinit();

    const joined_msg: suharyk_prot.params.sa_broadcast_join = .{
        .name = join_req.name,
    };
    const left_msg: suharyk_prot.params.sa_broadcast_leave = .{
        .name = client.player.name,
    };
    client.broadcast(joined_msg);
    defer client.broadcast(left_msg);
    std.log.debug(
        "{s} left the game",
        .{ join_req.name, join_req.prot_ver },
    );
    while (!client.player.disconnect) {
        // TODO: handle client actions
    }
}

fn broadcast(client: Client, info: anytype) !void {
    for (Listener.clients.items) |other_client| {
        if (other_client.id != client.id) {
            var client_bridge = other_client.player.suharyk_bridge;
            try client_bridge.send(info);
        }
    }
}
