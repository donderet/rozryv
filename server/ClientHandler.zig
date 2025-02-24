const std = @import("std");
const suharyk_prot = @import("suharyk");
const Game = @import("Game.zig");
const Listener = @import("Listener.zig");

const ClientHandler = @This();

id: usize,
connection: std.net.Server.Connection,
allocator: std.mem.Allocator,
game: Game,

pub fn init(
    con: std.net.Server.Connection,
    a: std.mem.Allocator,
) ClientHandler {
    return ClientHandler{
        .connection = con,
        .allocator = a,
        .game = Game.init(a),
        .id = Listener.clients.items.len,
    };
}

pub fn handle(handler: *const ClientHandler) !void {
    const client_writer = handler.connection.stream.writer();
    const client_reader = handler.connection.stream.reader();
    var join_req: suharyk_prot.params.req_join = undefined;
    try suharyk_prot.Suharyk.deserialize(&join_req, client_reader);
    std.log.debug(
        "{s} joined the game with protocol version {d}",
        .{ join_req.name, join_req.prot_ver },
    );
    while (true) {
        const msg = try client_reader.readUntilDelimiterOrEofAlloc(
            handler.allocator,
            '\n',
            65535,
        ) orelse break;
        defer handler.allocator.free(msg);

        std.log.info("Recieved message: \"{s}\"", .{msg});
        try client_writer.writeAll("Your message is: ");
        try client_writer.writeAll(msg);
    }
}

// pub fn sendSuharyk(suharyk: suharyk_prot.suharyk_t) !void {}
