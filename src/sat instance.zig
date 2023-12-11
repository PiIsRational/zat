const std = @import("std");
const Allocator = std.mem.Allocator;

const defaultResult = [_]Variable{ Variable.FALSE, Variable.TRUE, Variable.TRUE, Variable.FALSE, Variable.TRUE, Variable.TRUE, Variable.FALSE, Variable.TRUE, Variable.TRUE, Variable.FALSE, Variable.TRUE, Variable.TRUE };

pub const SatInstance = struct {
    allocator: Allocator,
    clauses: std.ArrayList(Clause),
    variables: []Variable,

    const Self = @This();

    pub fn new(allocator: Allocator, clauses: std.ArrayList(Clause), variables: []Variable) SatInstance {
        return SatInstance{
            .allocator = allocator,
            .clauses = clauses,
            .variables = variables,
        };
    }

    pub fn solve(self: Self) SatResult {
        // TODO implement DPLL
        // find unary clauses and propagate
        while (self.has_unary()) {}

        return SatResult{ .SAT = defaultResult[0..] };
    }

    pub fn has_unary(self: Self) bool {
        _ = self;
        return false;
    }

    pub fn format(
        self: Self,
        comptime fmt: []const u8,
        options: std.fmt.FormatOptions,
        writer: anytype,
    ) !void {
        _ = options;
        _ = fmt;

        for (self.clauses.items, 0..) |clause, i| {
            if (i != 0) {
                try writer.print(" & ", .{});
            }

            try writer.print("({s})", .{clause});
        }
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

    pub fn format(
        self: Self,
        comptime fmt: []const u8,
        options: std.fmt.FormatOptions,
        writer: anytype,
    ) !void {
        _ = options;
        _ = fmt;

        switch (self) {
            .SAT => |solution| {
                for (solution, 1..) |var_state, var_num| {
                    if (var_num != 1) {
                        try writer.print(" ", .{});
                    }

                    try writer.print("{s}{}", .{ var_state, var_num });
                }
            },
            .UNSAT => {},
        }
    }
};

pub const Clause = struct {
    literals: std.ArrayList(i32),
    const Self = @This();

    pub fn format(
        self: Self,
        comptime fmt: []const u8,
        options: std.fmt.FormatOptions,
        writer: anytype,
    ) !void {
        _ = options;
        _ = fmt;

        for (self.literals.items, 0..) |literal, i| {
            try writer.print("{d}", .{literal});

            if (i != self.literals.items.len - 1) {
                try writer.print(" | ", .{});
            }
        }
    }
};

pub const Variable = enum(i8) {
    UNASSIGNED = -1,
    FALSE,
    TRUE,

    const Self = @This();

    pub fn format(
        self: Self,
        comptime fmt: []const u8,
        options: std.fmt.FormatOptions,
        writer: anytype,
    ) !void {
        _ = options;
        _ = fmt;

        if (self == Variable.FALSE) {
            try writer.print("-", .{});
        }
    }
};
