const std = @import("std");
const SatInstance = @import("sat instance.zig").SatInstance;
const InstanceBuilder = @import("instance builder.zig").InstanceBuilder;
const fs = std.fs;
const OpenError = fs.File.OpenError;
const Allocator = std.mem.Allocator;

pub fn main() !void {
    const stdout = std.io.getStdOut().writer();
    try stdout.print(">>>>---Hello SAT!---<<<<\n", .{});

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const args = try std.process.argsAlloc(gpa.allocator());
    defer std.process.argsFree(gpa.allocator(), args);

    for (args[1..args.len]) |path| {
        try stdout.print("c FILE: {s}\n", .{path});
        var instance = try InstanceBuilder.load_from_file(gpa.allocator(), path);
        var result = instance.solve();
        _ = result;

        //TODO: print the result
    }

    try stdout.print("finished execution!", .{});
}
