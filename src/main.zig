const std = @import("std");
const Allocator = std.mem.Allocator;

pub fn main() !void {
    const stdout = std.io.getStdOut().writer();
    const stdin = std.io.getStdIn().reader();

    try stdout.print(">>>>---Hello SAT!---<<<<\n", .{});

    const read_bytes = stdin.readAll();
    _ = read_bytes;
}

pub fn solve(inst: SatInstance) SatResult {
    // find unary clauses and propagate
    while (inst.has_unary()) {}
}

const SatInstance = struct {
    allpcator: Allocator,
    clauses: std.ArrayList(Clause),
    variables: []VarState,

    pub fn new(allocator: Allocator) SatInstance {
        return SatInstance{
            .allocator = allocator,
        };
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
