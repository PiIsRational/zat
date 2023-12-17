const std = @import("std");
const Literal = @import("literal.zig").Literal;
const Variable = @import("varaible.zig").Variable;

pub const Clause = struct {
    literals: std.ArrayList(Literal),
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
            try writer.print("{s}", .{literal});

            if (i != self.literals.items.len - 1) {
                try writer.print(" | ", .{});
            }
        }
    }

    pub fn isUnitClause(self: Self, variables: []Variable, literal: *Literal) bool {
        return self.setVariables(variables, literal) == self.literals.items.len - 1;
    }

    pub fn isEmptyClause(self: Self, variables: []Variable) bool {
        var lit = Literal{ .is_negated = false, .variable = 0 };
        return self.setVariables(variables, &lit) == self.literals.items.len;
    }

    fn setVariables(self: Self, variables: []Variable, last_unassigned: *Literal) usize {
        var set_items: usize = 0;

        for (self.literals.items) |item| {
            if (variables[item.variable] != Variable.UNASSIGNED) {
                set_items += 1;
            } else {
                last_unassigned.* = item;
            }

            if (variables[item.variable].isTrue() != item.is_negated) {
                return self.literals.items.len;
            }
        }

        return set_items;
    }
};
