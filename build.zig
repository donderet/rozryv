const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});

    const optimize = b.standardOptimizeOption(.{});

    const suharyk_mod = b.addModule("suharyk", .{
        .root_source_file = b.path("suharyk/protocol.zig"),
        .target = target,
        .optimize = optimize,
    });

    const server_exe = b.addExecutable(.{
        .name = "rozryv-server",
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
    const raylib_dep = b.dependency("raylib-zig", .{
        .target = target,
        .optimize = optimize,
    });

    const raylib = raylib_dep.module("raylib"); // main raylib module
    const raygui = raylib_dep.module("raygui"); // raygui module
    const raylib_artifact = raylib_dep.artifact("raylib"); // raylib C library
    game_exe.linkLibrary(raylib_artifact);
    game_exe.root_module.addImport("raylib", raylib);
    game_exe.root_module.addImport("raygui", raygui);
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
