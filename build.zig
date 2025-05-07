const std = @import("std");
const raylib = @import("raylib");
pub const std_options: std.Options = .{
    .log_level = .debug,
};

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});

    const optimize = b.standardOptimizeOption(.{});

    const lb: raylib.LinuxDisplayBackend = if (optimize == .Debug) .Wayland else .Both;
    const raylib_dep = b.dependency("raylib", .{
        .target = target,
        .optimize = optimize,
        .linux_display_backend = lb,
    });
    const raygui_dep = b.dependency("raygui", .{
        .target = target,
        .optimize = optimize,
    });
    const raylib_artifact = raylib_dep.artifact("raylib");
    raylib.addRaygui(b, raylib_artifact, raygui_dep);

    var server_exe_name_buf: [24]u8 = undefined;
    const server_exe_name = std.fmt.bufPrint(
        &server_exe_name_buf,
        "rozryv-server{s}",
        .{target.result.os.tag.exeFileExt(.x86_64)},
    ) catch @panic("OOM");

    const server_options = b.addOptions();
    server_options.addOption([]const u8, "exe_name", server_exe_name);

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

    var assets_copy = b.addInstallDirectory(
        .{
            .source_dir = b.path("assets/"),
            .install_dir = .bin,
            .install_subdir = "assets",
        },
    );

    const game_exe = b.addExecutable(.{
        .name = "rozryv",
        .root_source_file = b.path("game/main.zig"),
        .target = target,
        .optimize = optimize,
        .use_lld = false,
    });
    game_exe.root_module.addOptions("server_options", server_options);
    game_exe.linkLibrary(raylib_dep.artifact("raylib"));
    game_exe.root_module.addImport("suharyk", suharyk_mod);
    game_exe.root_module.addOptions("server", server_options);
    game_exe.step.dependOn(&server_exe.step);
    game_exe.step.dependOn(&assets_copy.step);

    b.installArtifact(game_exe);

    {
        const run_cmd = b.addRunArtifact(game_exe);

        run_cmd.step.dependOn(b.getInstallStep());

        run_cmd.setCwd(.{
            .cwd_relative = b.exe_dir,
        });

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
