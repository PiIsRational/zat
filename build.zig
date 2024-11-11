const std = @import("std");

const SAT_EXIT = 10;
const UNSAT_EXIT = 20;

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});
    const main_path = "src/main.zig";

    const exe = b.addExecutable(.{
        .name = "zat",
        .root_source_file = b.path(main_path),
        .target = target,
        .optimize = optimize,
        .omit_frame_pointer = false,
    });

    const options = b.addOptions();

    const no_assert = switch (optimize) {
        .ReleaseFast, .ReleaseSmall => true,
        .Debug, .ReleaseSafe => false,
    } or b.option(bool, "no-assert", "nullifies big assert clauses (default: false)") orelse
        false;

    options.addOption(std.builtin.OptimizeMode, "optim", optimize);
    options.addOption(bool, "no_assert", no_assert);
    exe.root_module.addOptions("build_opt", options);

    b.installArtifact(exe);
    const run_cmd = b.addRunArtifact(exe);
    run_cmd.step.dependOn(b.getInstallStep());

    if (b.args) |args| run_cmd.addArgs(args);

    const run_step = b.step("run", "Run the app");
    run_step.dependOn(&run_cmd.step);

    // unit tests

    const unit_tests = b.addTest(.{
        .root_source_file = b.path(main_path),
        .target = target,
        .optimize = optimize,
    });

    const run_unit_tests = b.addRunArtifact(unit_tests);

    // full tests
    const test_step = b.step("test", "Run unit tests");
    const sat_path = "test/sat/";
    const unsat_path = "test/unsat/";

    for ([_]struct { []const u8, bool }{
        .{ sat_path, true },
        .{ unsat_path, false },
    }) |tuple| {
        const path, const is_sat = tuple;

        const dir = std.fs.cwd().openDir(path, .{ .iterate = true }) catch unreachable;
        var walker = dir.walk(b.allocator) catch unreachable;
        defer walker.deinit();

        while (walker.next() catch unreachable) |entry| {
            switch (entry.kind) {
                .file => {},
                else => continue,
            }

            const file_path = b.fmt("{s}{s}", .{ path, entry.basename });
            const sat_cmd = b.addRunArtifact(exe);
            sat_cmd.addFileArg(b.path(file_path));
            sat_cmd.expectExitCode(switch (is_sat) {
                true => SAT_EXIT,
                false => UNSAT_EXIT,
            });

            test_step.dependOn(&sat_cmd.step);
        }
    }

    test_step.dependOn(&run_unit_tests.step);
}
