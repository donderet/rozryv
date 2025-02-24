const std = @import("std");
const suharyk_prot = @import("suharyk");
const Game = @import("Game.zig");
const Listener = @import("Listener.zig");

const ClientHandler = @This();

id: usize,
connection: std.net.Server.Connection,
allocator: std.mem.Allocator,
player: Game.Player = undefined,

pub fn init(
    con: std.net.Server.Connection,
    a: std.mem.Allocator,
) ClientHandler {
    return ClientHandler{
        .connection = con,
        .allocator = a,
        .id = Listener.clients.items.len,
    };
}

pub fn handle(handler: *ClientHandler) !void {
    var suharyk_bridge = suharyk_prot.Bridge.init(handler.connection, handler.allocator);

    var join_req: suharyk_prot.params.req_join = undefined;
    try suharyk_bridge.recieve(&join_req);
    std.log.debug(
        "{s} joined the game with protocol version {d}",
        .{ join_req.name, join_req.prot_ver },
    );
    const protocol_matches = join_req.prot_ver == suharyk_prot.VERSION;
    const resp: suharyk_prot.params.resp_join = .{
        .ok = protocol_matches,
        .members = if (protocol_matches) Game.name_list.items else null,
    };
    try suharyk_bridge.send(resp);
    handler.player = try Game.Player.init(handler.id, join_req.name, suharyk_bridge);
    defer handler.player.deinit();
    while (true) {
        const msg = try suharyk_bridge.br.reader().readUntilDelimiterOrEofAlloc(
            handler.allocator,
            '\n',
            65535,
        ) orelse break;
        defer handler.allocator.free(msg);

        std.log.info("Recieved message: \"{s}\"", .{msg});
    }
}
