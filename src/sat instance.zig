const std = @import("std");
const Allocator = std.mem.Allocator;

const defaultResult = [_]Variable{ Variable.FALSE, Variable.TRUE, Variable.TRUE, Variable.FALSE, Variable.TRUE, Variable.TRUE, Variable.FALSE, Variable.TRUE, Variable.TRUE, Variable.FALSE, Variable.TRUE, Variable.TRUE };

pub const SatInstance = struct {
    allocator: Allocator,
    clauses: std.ArrayList(Clause),
    variables: []Variable,

    pub fn new(allocator: Allocator, clauses: std.ArrayList(Clause), variables: []Variable) SatInstance {
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

        return SatResult{ .SAT = defaultResult[0..] };
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
    UNSAT: bool,
    SAT: []const Variable,

    const Self = @This();

    pub fn toString(self: Self) [:0]const u8 {
        return switch (self) {
            .SAT => "SATISFIABLE",
            .UNSAT => "UNSATISFIABLE",
        };
    }

    pub fn getSolution(self: Self, allocator: Allocator) ![:0]const u8 {
        return switch (self) {
            .SAT => |solution| blk: {
                var len: usize = 0;
                for (solution, 1..) |result, i| {
                    len += @as(usize, (if (i != 1) 1 else 0)) + result.getStringLen(i);
                }

                const output: [:0]u8 = try allocator.allocSentinel(u8, len, 0);
                len = 0;
                for (solution, 1..) |result, i| {
                    if (i != 1) {
                        output[len] = ' ';
                        len += 1;
                    }
                    _ = result.addToString(i, &len, output);
                }
                break :blk output;
            },
            .UNSAT => "",
        };
    }
};

pub const Clause = struct {
    literals: std.ArrayList(i32),
    const Self = @This();

    pub fn toString(self: Self, allocator: Allocator) ![:0]u8 {
        var len: usize = 0;
        for (self.literals.items, 0..) |literal, i| {
            if (literal < 0) {
                len += Variable.FALSE.getStringLen(@intCast(-literal));
            } else {
                len += Variable.TRUE.getStringLen(@intCast(literal));
            }

            if (i != 0) {
                len += 3;
            }
        }

        const output: [:0]u8 = try allocator.allocSentinel(u8, len, 0);
        var index: usize = 0;
        for (self.literals.items, 0..) |literal, i| {
            if (literal < 0) {
                _ = Variable.FALSE.addToString(@intCast(-literal), &index, output);
            } else {
                _ = Variable.TRUE.addToString(@intCast(literal), &index, output);
            }

            if (i != 0) {
                output[index + 0] = ' ';
                output[index + 1] = '|';
                output[index + 2] = ' ';
                index += 3;
            }
        }

        return output;
    }
};

pub const Variable = enum(i8) {
    UNASSIGNED = -1,
    FALSE,
    TRUE,

    const Self = @This();

    pub fn getStringLen(self: Self, num: usize) usize {
        var len = @as(usize, if (self == Variable.FALSE) 1 else 0);
        var number = num;

        if (number == 0) {
            return len + 1;
        }

        while (number != 0) : (len += 1) {
            number /= 10;
        }

        return len;
    }

    pub fn addToString(self: Self, num: usize, index: *usize, slice: [:0]u8) [:0]u8 {
        var number = num;
        var len = self.getStringLen(num);
        if (self == Variable.FALSE) {
            slice[index.*] = '-';
            index.* += 1;
            len -= 1;
        }

        index.* += len;

        while (number != 0) {
            index.* -= 1;
            slice[index.*] = @intCast((number % 10) + 48);
            number /= 10;
        }

        index.* += len;

        return slice;
    }
};
