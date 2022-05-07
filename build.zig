const std = @import("std");

fn setupBackend(b: *std.build.Builder, exe: *std.build.LibExeObjStep) !void {
    const backend_name_input = b.option([]const u8, "backend", "The backend to use") orelse "raylib";

    const backends_dir = try std.fs.cwd().openDir("src/backends", .{ .iterate = true });

    var stdout = std.io.bufferedWriter(std.io.getStdOut().writer()).writer();
    try stdout.print("Unknown backend.\nAvailable backends:\n", .{});

    var backends_dir_iterator = backends_dir.iterate();
    while (try backends_dir_iterator.next()) |file| {
        var backend_name = std.mem.split(u8, file.name, ".").next() orelse unreachable;
        if (std.mem.eql(u8, backend_name, backend_name_input)) {
            if (std.mem.eql(u8, backend_name, "raylib")) {
                exe.linkLibC();
                exe.linkSystemLibrary("raylib");
            }

            exe.addPackagePath(
                "backend",
                try std.fmt.allocPrint(b.allocator, "src/backends/{s}.zig", .{backend_name}),
            );

            return;
        }
        try stdout.print("    {s}\n", .{backend_name});
    }

    try stdout.context.flush();
    std.process.exit(1);
}

pub fn build(b: *std.build.Builder) !void {
    // Standard target options allows the person running `zig build` to choose
    // what target to build for. Here we do not override the defaults, which
    // means any target is allowed, and the default is native. Other options
    // for restricting supported target set are available.
    const target = b.standardTargetOptions(.{});

    // Standard release options allow the person running `zig build` to select
    // between Debug, ReleaseSafe, ReleaseFast, and ReleaseSmall.
    const mode = b.standardReleaseOptions();
    const exe = b.addExecutable("anyOS", "src/main.zig");
    exe.setTarget(target);
    exe.setBuildMode(mode);
    try setupBackend(b, exe);
    exe.install();

    const run_cmd = exe.run();
    run_cmd.step.dependOn(b.getInstallStep());
    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    const run_step = b.step("run", "Run the app");
    run_step.dependOn(&run_cmd.step);

    const exe_tests = b.addTest("src/main.zig");
    exe_tests.setTarget(target);
    exe_tests.setBuildMode(mode);

    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&exe_tests.step);
}
