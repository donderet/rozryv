const std = @import("std");

pub inline fn indexOfBackwards(str: []u8, char: u8) usize {
    if (str.len == 0) return 0;
    var i: usize = str.len - 1;
    while (i != 0) : (i -= 1) {
        if (str[i] == char) return i;
    }
    return 0;
}

pub inline fn indexOfForwards(str: []u8, char: u8) usize {
    for (0..str.len) |i| {
        if (str[i] == char) return i;
    }
    return 0;
}

pub inline fn len(str: []u8) usize {
    return indexOfForwards(str, 0);
}
