const std = @import("std");
const Allocator = std.mem.Allocator;
const Variable = @import("variable.zig").Variable;
const Clause = @import("clause.zig").Clause;
const SatResult = @import("sat_result.zig").SatResult;
const Literal = @import("literal.zig").Literal;

const defaultResult = [_]Variable{ .FORCE_FALSE, .FORCE_TRUE };

pub const SatInstance = struct {
    allocator: Allocator,
    clauses: std.ArrayList(Clause),
    setting_order: std.ArrayList(usize),
    variables: []Variable,

    const Self = @This();

    pub fn init(allocator: Allocator, variables: []Variable) SatInstance {
        return SatInstance{
            .allocator = allocator,
            .clauses = std.ArrayList(Clause).init(allocator),
            .variables = variables,
            .setting_order = std.ArrayList(usize).init(allocator),
        };
    }

    pub fn solve(self: *Self) !SatResult {
        _ = self;
        return SatResult{ .UNSAT = true };
    }

    fn verify(self: Self) bool {
        for (self.clauses.items) |clause| {
            var found_one: bool = false;
            for (clause.literals) |literal| {
                if (self.variables[literal.variable].isTrue() != literal.is_negated) {
                    found_one = true;
                    break;
                }
            }

            if (!found_one) {
                return false;
            }
        }

        return true;
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
