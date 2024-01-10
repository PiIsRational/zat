const std = @import("std");
const Allocator = std.mem.Allocator;
const Variable = @import("variable.zig").Variable;
const Literal = @import("literal.zig").Literal;
const Clause = @import("clause.zig").Clause;

pub const Impls = struct {
    impls: []Impl,

    const Self = @This();

    pub fn init(allocator: Allocator, var_count: usize) !Self {
        var impls = try allocator.alloc(Impl, var_count);
        @memset(impls, Impl.init());
        return Impls{
            .impls = impls,
        };
    }

    pub fn getFromLit(self: Self, literal: Literal) *Variable {
        return self.getVar(literal.variable);
    }

    pub fn getVar(self: Self, variable: usize) *Variable {
        return &self.impls[variable].variable;
    }

    pub fn set(self: *Self, variable: usize, value: Variable, reason: Clause) void {
        self.impls[variable] = Impl{
            .reason = reason,
            .variable = value,
        };
    }
};

pub const Impl = struct {
    reason: Clause,
    variable: Variable,

    const Self = @This();

    pub fn init() Self {
        return Impl{
            .reason = Clause.getNull(),
            .variable = .UNASSIGNED,
        };
    }
};
