const std = @import("std");
const SatInstance = @import("sat instance.zig").SatInstance;
const InstanceBuilder = @import("instance builder.zig").InstanceBuilder;
const fs = std.fs;
const OpenError = fs.File.OpenError;
const Allocator = std.mem.Allocator;

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
    }

    try stdout.print("c FILE: {s}\n", .{args[1]});
    var instance = try InstanceBuilder.load_from_file(gpa.allocator(), args[1]);
    var result = instance.solve();

    try stdout.print("s {s}\n", .{result.toString()});
    const solution = try result.getSolution(gpa.allocator());

    switch (result) {
        .SAT => try stdout.print("v {s}\n", .{solution}),
        .UNSAT => {},
    }

    gpa.allocator().free(solution);

    switch (result) {
        .SAT => std.os.exit(SAT_EXIT),
        .UNSAT => std.os.exit(UNSAT_EXIT),
    }
}
