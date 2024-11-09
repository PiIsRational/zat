const std = @import("std");
const Allocator = std.mem.Allocator;
const Variable = @import("variable.zig").Variable;
const Literal = @import("literal.zig").Literal;
const Clause = @import("clause.zig").Clause;

pub const Impls = struct {
    impls: []Impl,

    pub fn init(allocator: Allocator, var_count: usize) !Impls {
        const impls = try allocator.alloc(Impl, var_count);
        @memset(impls, Impl.init());

        return .{ .impls = impls };
    }

    pub fn getFromLit(self: Impls, literal: Literal) *Variable {
        return self.getVar(literal.variable);
    }

    pub fn getVar(self: Impls, variable: usize) *Variable {
        return &self.impls[variable].variable;
    }

    pub fn getReason(self: Impls, variable: usize) *Reason {
        return &self.impls[variable].reason;
    }

    pub fn set(self: *Impls, variable: usize, value: Variable, reason: Reason) void {
        self.impls[variable] = .{ .reason = reason, .variable = value };
    }
};

pub const Reason = union(enum) {
    unary,
    binary: Literal,
    other: Clause,
};

pub const Conflict = union(enum) {
    binary: [2]Literal,
    other: Clause,
};

pub const Impl = struct {
    reason: Reason,
    variable: Variable,

    pub fn init() Impl {
        return .{ .reason = .unary, .variable = .unassigned };
    }
};
