const std = @import("std");
const suharyk = @import("suharyk");
const ClientPayload = suharyk.packet.ClientPayload;
const ServerPayload = suharyk.packet.ServerPayload;
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
    var suharyk_bridge = suharyk.Bridge.init(client.connection, client.allocator);

    var join_req: suharyk.client_hello = undefined;
    try suharyk_bridge.recieve(&join_req);
    const protocol_matches = join_req.prot_ver == suharyk.VERSION;
    const resp: suharyk.server_hello = .{
        .ok = protocol_matches,
        .members = if (protocol_matches) Game.name_list.items else null,
    };
    try suharyk_bridge.send(resp);
    if (!resp.ok) {
        std.log.debug(
            "Protocol version mismatched for player {s}",
            .{join_req.name},
        );
        return;
    }
    client.player = try Game.Player.init(client.id, join_req.name, suharyk_bridge);
    defer client.player.deinit();

    std.log.debug(
        "{s} joined the game",
        .{join_req.name},
    );

    const joined_msg: ServerPayload = .{
        .BroadcastJoin = .{
            .name = join_req.name,
        },
    };
    const left_msg: ServerPayload = .{
        .BroadcastLeave = .{
            .name = client.player.name,
        },
    };
    client.broadcast(joined_msg);
    defer {
        client.broadcast(left_msg);
        std.log.debug(
            "{s} left the game",
            .{join_req.name},
        );
    }
    while (!client.player.disconnect) {
        // TODO: handle client actions
        var pl: suharyk.packet.ClientPayload = undefined;
        try client.player.suharyk_bridge.recieve(&pl);
    }
}

fn broadcast(client: Client, info: anytype) void {
    for (Listener.clients.items) |other_client| {
        if (other_client.id != client.id) {
            var client_bridge = other_client.player.suharyk_bridge;
            client_bridge.send(info) catch |e| {
                // Possibly, connection is closed from other thread
                std.log.debug("Failed to broadcast: {any}", .{e});
            };
        }
    }
}
