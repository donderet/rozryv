const std = @import("std");
const suharyk = @import("suharyk");

const ClientHandler = @This();
const obs_t = @TypeOf(fn (*ClientHandler) void);
server: std.net.Server = undefined,
allocator: std.mem.Allocator = undefined,

on_connection_observers: std.ArrayList(obs_t) = undefined,

pub fn init(s: std.net.Server, a: std.mem.Allocator) ClientHandler {
    return ClientHandler{
        .server = s,
        .allocator = a,
        .on_connection_observers = std.ArrayList(obs_t).init(a),
    };
}

pub fn deinit(handler: *ClientHandler) void {
    handler.on_connection_observers.deinit();
}

pub fn handle(handler: *ClientHandler) !void {
    var client = try handler.server.accept();
    for (handler.on_connection_observers) |onCon| {
        onCon(*handler);
    }
    defer client.stream.close();

    const client_reader = client.stream.reader();
    const client_writer = client.stream.writer();
    while (true) {
        const msg = try client_reader.readUntilDelimiterOrEofAlloc(
            handler.allocator,
            '\n',
            suharyk.MAX_PACKET_LEN,
        ) orelse break;
        defer handler.allocator.free(msg);

        std.log.info("Recieved message: \"{s}\"", .{msg});
        try client_writer.writeAll("Your message is: ");
        try client_writer.writeAll(msg);
    }
}
