const std = @import("std");
const SatInstance = @import("sat instance.zig").SatInstance;
const InstanceBuilder = @import("instance builder.zig").InstanceBuilder;
const Literal = @import("literal.zig").Literal;
const ClauseHeader = @import("clause header.zig").ClauseHeader;
const Garbage = @import("mem garbage.zig").MemGarbage;

const Cell = @import("mem cell.zig").MemoryCell;
const fs = std.fs;
const OpenError = fs.File.OpenError;
const Allocator = std.mem.Allocator;

const SAT_EXIT = 10;
const UNSAT_EXIT = 20;

pub fn main() !void {
    const stdout = std.io.getStdOut().writer();
    try stdout.print("SAT solver\n", .{});

    try stdout.print("cell size: {}, literal size: {}, clause header: {}, garbage: {}\n", .{ @sizeOf(Cell), @sizeOf(Literal), @sizeOf(ClauseHeader), @sizeOf(Garbage) });
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const args = try std.process.argsAlloc(gpa.allocator());
    defer std.process.argsFree(gpa.allocator(), args);

    if (args.len != 2) {
        try stdout.print("(ERROR) usage: ./SAT Test DPLL.exe <path>", .{});
    }

    try stdout.print("c FILE: {s}\n", .{args[1]});
    var instance = try InstanceBuilder.load_from_file(gpa.allocator(), args[1]);
    var result = try instance.solve();

    try stdout.print("s {s}\n", .{result.toString()});

    switch (result) {
        .SAT => try stdout.print("v {s}\n", .{result}),
        .UNSAT => {},
    }

    switch (result) {
        .SAT => std.os.exit(SAT_EXIT),
        .UNSAT => std.os.exit(UNSAT_EXIT),
    }
}
