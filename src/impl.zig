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
        return &self.get(variable).variable;
    }

    pub fn getReason(self: Impls, variable: usize) *Reason {
        return &self.get(variable).reason;
    }

    pub fn getChoiceCount(self: Impls, variable: usize) *usize {
        return &self.get(variable).choice_count;
    }

    pub fn get(self: Impls, variable: usize) *Impl {
        return &self.impls[variable];
    }

    pub fn getLit(self: Impls, variable: usize) Literal {
        return Literal.init(self.getVar(variable).isFalse(), @intCast(variable));
    }

    pub fn set(
        self: *Impls,
        variable: usize,
        value: Variable,
        reason: Reason,
        choice_count: usize,
    ) void {
        self.impls[variable] = .{
            .reason = reason,
            .variable = value,
            .choice_count = choice_count,
        };
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
    choice_count: usize,
    variable: Variable,

    pub fn init() Impl {
        return .{ .reason = .unary, .variable = .unassigned, .choice_count = 0 };
    }
};
