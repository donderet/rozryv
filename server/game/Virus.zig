const std = @import("std");
const suharyk = @import("suharyk");
const RandomTickable = @import("RandomTickable.zig");
const Virus = @This();
const SuharykVirus = suharyk.entities.Virus;

suh_virus: SuharykVirus,

fn getRndInterval(self: Virus) u16 {
    if (self.suh_virus.fast)
        return 1
    else
        return 2;
}

pub fn randomTickable(self: Virus) RandomTickable {
    return .{
        .ctx = self,
        .vtable = .{
            .interval = self.getRndInterval(),
            .onRandomTick = &onRandomTick,
        },
    };
}

fn onRandomTick(self: Virus) void {
    _ = self;
}
