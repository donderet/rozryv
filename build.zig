const std = @import("std");

pub fn build(b: *std.Build) void {
    const server_exe_name = "rozryv-server";
    const server_options = b.addOptions();
    server_options.addOption([]const u8, "exe_name", server_exe_name);

    const target = b.standardTargetOptions(.{});

    const optimize = b.standardOptimizeOption(.{});

    const suharyk_mod = b.addModule("suharyk", .{
        .root_source_file = b.path("suharyk/protocol.zig"),
        .target = target,
        .optimize = optimize,
    });

    const server_exe = b.addExecutable(.{
        .name = server_exe_name,
        .root_source_file = b.path("server/main.zig"),
        .target = target,
        .optimize = optimize,
    });
    server_exe.root_module.addImport("suharyk", suharyk_mod);
    b.installArtifact(server_exe);

    const game_exe = b.addExecutable(.{
        .name = "rozryv",
        .root_source_file = b.path("game/main.zig"),
        .target = target,
        .optimize = optimize,
    });
    game_exe.root_module.addImport("suharyk", suharyk_mod);
    game_exe.root_module.addOptions("server", server_options);

    b.installArtifact(game_exe);

    {
        const run_cmd = b.addRunArtifact(game_exe);

        run_cmd.step.dependOn(b.getInstallStep());

        if (b.args) |args| {
            run_cmd.addArgs(args);
        }

        const run_step = b.step("run", "Run the app");
        run_step.dependOn(&run_cmd.step);
    }
    {
        const run_cmd = b.addRunArtifact(server_exe);

        run_cmd.step.dependOn(b.getInstallStep());

        if (b.args) |args| {
            run_cmd.addArgs(args);
        }

        const run_step = b.step("srun", "Run the server");
        run_step.dependOn(&run_cmd.step);
    }
}
