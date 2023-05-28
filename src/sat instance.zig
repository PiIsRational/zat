const std = @import("std");
const Allocator = std.mem.Allocator;

pub const SatInstance = struct {
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

pub const PossibleResults = enum {
    UNSAT,
    SAT,
};

pub const SatResult = union(PossibleResults) {
    SAT: []VarState,
    UNSAT: bool,
};

pub const Clause = struct {
    literals: std.ArrayList(i32),
};

pub const VarState = enum(i8) {
    UNASSIGNED = -1,
    FALSE,
    TRUE,
};
