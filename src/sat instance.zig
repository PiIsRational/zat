const std = @import("std");
const Allocator = std.mem.Allocator;
const Variable = @import("variable.zig").Variable;
const Clause = @import("clause.zig").Clause;
const ClauseDb = @import("clause db.zig").ClauseDb;
const SatResult = @import("sat_result.zig").SatResult;
const Literal = @import("literal.zig").Literal;
const BinClauses = @import("binary clauses.zig").BinClauses;
const WatchList = @import("watch.zig").WatchList;

const defaultResult = [_]Variable{ .FORCE_FALSE, .FORCE_TRUE };

pub const SatInstance = struct {
    allocator: Allocator,
    clauses: ClauseDb,
    binary_clauses: BinClauses,
    watch: WatchList,
    variables: []Variable,
    setting_order: std.ArrayList(usize),

    const Self = @This();

    pub fn init(
        allocator: Allocator,
        variables: usize,
    ) !SatInstance {
        return SatInstance{
            .allocator = allocator,
            .clauses = try ClauseDb.init(allocator, variables),
            .binary_clauses = try BinClauses.init(allocator, variables),
            .watch = try WatchList.init(variables, allocator),
            .variables = try allocator.alloc(Variable, variables),
            .setting_order = std.ArrayList(usize).init(allocator),
        };
    }

    pub fn solve(self: *Self) !SatResult {
        _ = self;
        return SatResult{ .UNSAT = false };
    }

    /// set `variable` to `state`.
    ///
    /// iff was able to set returns true
    fn set(self: *Self, variable: usize, state: Variable) !bool {
        if (self.variables[variable] == state) {
            return true;
        }

        if (self.variables[variable] != .UNASSIGNED) {
            return false;
        }

        self.variables[variable] = state;
        try self.setting_order.append(variable);
    }

    pub fn clauseCount(self: Self) usize {
        return self.binary_clauses.len + self.clauses.getLength();
    }

    pub fn format(
        self: Self,
        comptime fmt: []const u8,
        options: std.fmt.FormatOptions,
        writer: anytype,
    ) !void {
        _ = options;
        _ = fmt;

        for (self.clauses.clauses.items, 0..) |clause, i| {
            if (i != 0) {
                try writer.print(" & ", .{});
            }

            try writer.print("({s})", .{clause});
        }

        if (self.binary_clauses.len == 0) {
            return;
        }

        try writer.print("\n{s}", .{self.binary_clauses});
    }
};
