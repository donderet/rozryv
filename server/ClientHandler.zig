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
    const stream_writer = handler.connection.stream.writer();
    const stream_reader = handler.connection.stream.reader();
    const bw = std.io.BufferedWriter(1024, std.net.Stream.Writer).writer();
    const writer = bw.any();

    var join_req: suharyk_prot.params.req_join = undefined;
    try suharyk_prot.Suharyk.deserialize(&join_req, writer);
    bw.flush();
    std.log.debug(
        "{s} joined the game with protocol version {d}",
        .{ join_req.name, join_req.prot_ver },
    );
    const resp: suharyk_prot.params.resp_join = .{
        .ok = join_req.prot_ver == suharyk_prot.VERSION,
        .members = null,
    };
    if (resp.ok) {
        resp.members = Game.name_list.items;
    }
    try suharyk_prot.Suharyk.serialize(resp, writer);
    bw.flush();
    while (true) {
        const msg = try stream_reader.readUntilDelimiterOrEofAlloc(
            handler.allocator,
            '\n',
            65535,
        ) orelse break;
        defer handler.allocator.free(msg);

        std.log.info("Recieved message: \"{s}\"", .{msg});
        try stream_writer.writeAll("Your message is: ");
        try stream_writer.writeAll(msg);
    }
}
