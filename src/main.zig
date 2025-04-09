const std = @import("std");
const assert = std.debug.assert;

const SatInstance = @import("sat_instance.zig").SatInstance;
const InstanceBuilder = @import("instance_builder.zig").InstanceBuilder;
const fs = std.fs;
const OpenError = fs.File.OpenError;
const Allocator = std.mem.Allocator;
const Watch = @import("watch.zig").Watch;
const ClauseHeuristic = @import("clause.zig").ClauseHeuristic;

const ERROR_EXIT = 1;
const SAT_EXIT = 10;
const UNSAT_EXIT = 20;

const builtin = @import("builtin");

var debug_allocator: std.heap.DebugAllocator(.{}) = .init;

pub fn main() !void {
    const gpa, const is_debug = switch (builtin.mode) {
        .Debug, .ReleaseSafe => .{ debug_allocator.allocator(), true },
        .ReleaseFast, .ReleaseSmall => .{ std.heap.smp_allocator, true },
    };

    defer if (is_debug) {
        assert(debug_allocator.deinit() == .ok);
    };

    const stdout = std.io.getStdOut().writer();
    try stdout.print("c zat sat solver\n", .{});

    const args = try std.process.argsAlloc(gpa);
    defer std.process.argsFree(gpa, args);

    if (args.len != 2) {
        try stdout.print("c (ERROR) usage: ./zat <path>", .{});
        std.posix.exit(ERROR_EXIT);
    }

    try stdout.print("c FILE: {s}\n", .{args[1]});
    var instance = try InstanceBuilder.loadFromFile(gpa, args[1]);
    var result = try instance.solve();

    try instance.writeStats(stdout);
    try stdout.print("s {s}\n", .{result.toString()});

    switch (result) {
        .sat => {
            try stdout.print("v {s}\n", .{result});
            std.posix.exit(SAT_EXIT);
        },
        .unsat => std.posix.exit(UNSAT_EXIT),
    }
}

test {
    _ = @import("sat_instance.zig");
    _ = @import("instance_builder.zig");
}
