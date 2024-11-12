const std = @import("std");
const SatInstance = @import("sat_instance.zig").SatInstance;
const InstanceBuilder = @import("instance_builder.zig").InstanceBuilder;
const fs = std.fs;
const OpenError = fs.File.OpenError;
const Allocator = std.mem.Allocator;
const Watch = @import("watch.zig").Watch;

const ERROR_EXIT = 1;
const SAT_EXIT = 10;
const UNSAT_EXIT = 20;

pub fn main() !void {
    const stdout = std.io.getStdOut().writer();
    try stdout.print("SAT solver\n", .{});

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const args = try std.process.argsAlloc(gpa.allocator());
    defer std.process.argsFree(gpa.allocator(), args);

    if (args.len != 2) {
        try stdout.print("(ERROR) usage: ./SAT Test DPLL.exe <path>", .{});
        std.posix.exit(ERROR_EXIT);
    }

    try stdout.print("c FILE: {s}\n", .{args[1]});
    var instance = try InstanceBuilder.loadFromFile(gpa.allocator(), args[1]);
    var result = try instance.solve();

    try stdout.print("c {d} conflicts\n", .{instance.conflicts});
    try stdout.print("c {s}", .{Watch.stats});
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
