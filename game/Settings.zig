const std = @import("std");

const Settings = @This();

const settings_filename = "rozryv.cfg";
const settings_fields = [_][]const u8{
    "player_name",
    "last_address",
};

player_name_buf: [15:0]u8 = @splat(0),
player_name: []u8 = undefined,

last_address_buf: [255:0]u8 = @splat(0),
last_address: []u8 = undefined,

pub fn setPlayerName(self: *Settings, new_name: []const u8) void {
    setSliceFromBuf(
        &self.player_name,
        &self.player_name_buf,
        new_name,
    );
    self.save() catch |e| {
        std.log.debug("Can't save settings: {any}", .{e});
    };
}

pub fn setLastAddress(self: *Settings, new_address: []const u8) void {
    setSliceFromBuf(
        &self.last_address,
        &self.last_address_buf,
        new_address,
    );
    self.save() catch |e| {
        std.log.debug("Can't save settings: {any}", .{e});
    };
}

fn setSliceFromBuf(slice: *[]u8, buf: [:0]u8, src: []const u8) void {
    std.mem.copyForwards(u8, buf, src);
    slice.* = buf[0..src.len];
}

pub fn save(self: Settings) !void {
    const file = try std.fs.cwd().createFile(settings_filename, .{});
    defer file.close();

    const writer = file.writer();
    inline for (settings_fields) |field_name| {
        const val: []u8 = @field(self, field_name);
        try writer.print("{s}={s}\n", .{ field_name, val });
    }
}

pub fn restore(self: *Settings) !void {
    const file = try std.fs.cwd().openFile(settings_filename, .{});
    defer file.close();

    var file_buf: [512]u8 = undefined;
    const bytes_read = try file.reader().read(&file_buf);
    const file_content = file_buf[0..bytes_read];
    var line_iterator = std.mem.splitSequence(u8, file_content, "\n");

    while (line_iterator.next()) |line| {
        if (line.len == 0) continue;
        const eq_index = std.mem.indexOf(u8, line, "=") orelse continue;
        const key = std.mem.trim(u8, line[0..eq_index], " \r\t");
        const val = std.mem.trim(u8, line[eq_index + 1 ..], " \r\t");
        inline for (settings_fields) |field_name| {
            if (std.mem.eql(u8, key, field_name)) {
                const buffer_field_name = field_name ++ "_buf";
                var buf_f = &@field(self, buffer_field_name);
                for (&buf_f.*) |*el| el.* = 0;
                const bytes_to_copy = @min(val.len, buf_f.len);
                std.mem.copyForwards(
                    u8,
                    buf_f,
                    val[0..bytes_to_copy],
                );
                @field(self, field_name) = buf_f[0..bytes_to_copy];
                break;
            }
        }
    }
}
