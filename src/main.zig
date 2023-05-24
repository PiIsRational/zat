const std = @import("std");
const fs = std.fs;
const OpenError = fs.File.OpenError;
const Allocator = std.mem.Allocator;

pub fn main() !void {
    const stdout = std.io.getStdOut().writer();
    const stdin = std.io.getStdIn().reader();

    try stdout.print(">>>>---Hello SAT!---<<<<\n", .{});

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const args = std.process.argsAlloc(gpa.allocator());
    defer std.process.argsFree(gpa.allocator(), args);

    for (args) |path| {
        var instance = try SatInstance.load_from_file(gpa, path);
        var result = instance.solve();
        _ = result;

        //TODO: print the result
    }

    const read_bytes = stdin.readAll();
    _ = read_bytes;
}

const SatInstance = struct {
    allpcator: Allocator,
    clauses: std.ArrayList(Clause),
    variables: []VarState,

    pub fn new(allocator: Allocator, clauses: std.ArrayList(Clause), variables: []VarState) SatInstance {
        return SatInstance{
            .allocator = allocator,
            .clauses = clauses,
            .variables = variables,
        };
    }

    pub fn load_from_file(allocator: Allocator, path: [*:0]u8) OpenError!SatInstance {
        _ = allocator;
        var reader = try fs.cwd().openFile(path, .{});
        _ = reader;
    }

    pub fn solve(self: *SatInstance) SatResult {
        // TODO implement DPLL
        // find unary clauses and propagate
        while (self.has_unary()) {}
    }

    pub fn has_unary() bool {}
};

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

const VarState = enum(u8) {
    UNASSIGNED = -1,
    FALSE,
    TRUE,
};
