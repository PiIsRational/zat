const std = @import("std");
const fs = std.fs;
const OpenError = fs.File.OpenError;
const Allocator = std.mem.Allocator;
const BUFFER_SIZE = 10000;

pub fn main() !void {
    const stdout = std.io.getStdOut().writer();
    try stdout.print(">>>>---Hello SAT!---<<<<\n", .{});

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const args = try std.process.argsAlloc(gpa.allocator());
    defer std.process.argsFree(gpa.allocator(), args);

    for (args[1..args.len]) |path| {
        try stdout.print("c FILE: {s}\n", .{path});
        var instance = try SatInstance.load_from_file(gpa.allocator(), path);
        var result = instance.solve();
        _ = result;

        //TODO: print the result
    }

    try stdout.print("finished execution!", .{});
}

const SatInstance = struct {
    allocator: Allocator,
    clauses: std.ArrayList(Clause),
    variables: []VarState,

    pub fn new(allocator: Allocator, clauses: std.ArrayList(Clause), variables: []VarState) SatInstance {
        return SatInstance{
            .allocator = allocator,
            .clauses = clauses,
            .variables = variables,
        };
    }

    pub fn load_from_file(allocator: Allocator, path: []const u8) !SatInstance {
        var reader = try fs.cwd().openFile(path, .{});
        var buffer = try allocator.alloc(u8, BUFFER_SIZE);
        var characters = try reader.read(buffer);
        var index: usize = 0;
        var currline = std.ArrayList(u8).init(allocator);

        while (index < characters) {
            switch (buffer[index]) {
                '\n' => {
                    switch (currline.items[0]) {
                        'c' => {},
                        else => try print_list(currline),
                    }
                    currline.clearRetainingCapacity();
                },
                else => {
                    try currline.append(buffer[index]);
                },
            }

            index += 1;
            if (index == BUFFER_SIZE) {
                index = 0;
                characters = try reader.read(buffer);
            }
        }

        return SatInstance{
            .allocator = allocator,
            .clauses = std.ArrayList(Clause).init(allocator),
            .variables = try allocator.alloc(VarState, 0),
        };
    }

    pub fn solve(self: *SatInstance) SatResult {
        // TODO implement DPLL
        // find unary clauses and propagate
        while (self.has_unary()) {}

        return SatResult{ .UNSAT = true };
    }

    pub fn has_unary(self: *SatInstance) bool {
        _ = self;
        return false;
    }
};

fn print_list(list: std.ArrayList(u8)) !void {
    const stdout = std.io.getStdOut().writer();
    for (list.items) |item| {
        try stdout.print("{c}", .{item});
    }
    try stdout.print("\n", .{});
}

const PossibleResults = enum {
    UNSAT,
    SAT,
};

const SatResult = union(PossibleResults) {
    SAT: []VarState,
    UNSAT: bool,
};

const Clause = struct {
    literals: std.ArrayList(i32),
};

const VarState = enum(i8) {
    UNASSIGNED = -1,
    FALSE,
    TRUE,
};
