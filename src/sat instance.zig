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
    units: std.ArrayList(Literal),

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
            .units = std.ArrayList(Literal).init(allocator),
        };
    }

    pub fn solve(self: *Self) !SatResult {
        _ = self;
        return SatResult{ .UNSAT = false };
    }

    /// set `variable` to `state`.
    ///
    /// iff was able to set returns true
    pub fn set(self: *Self, variable: usize, state: Variable) !bool {
        if (self.variables[variable] == state) {
            return true;
        }

        if (self.variables[variable] != .UNASSIGNED) {
            return false;
        }

        self.variables[variable] = state;
        try self.setting_order.append(variable);
        self.watch.set(Literal.init(
            !state.isTrue(),
            @intCast(variable),
        ), self);

        return true;
    }

    pub fn clauseCount(self: Self) usize {
        return self.binary_clauses.len + self.clauses.getLength();
    }

    /// adds a clause to this sat instance
    ///
    /// **CAUTION** assumes that the literals of the clauses are not assigned
    pub fn addClause(self: *Self, literals: []Literal) !void {
        // append a unit clause
        if (literals.len == 1) {
            self.units.append(literals[1]);
            return;
        }

        // binary clause
        if (literals.len == 2) {
            try self.binary_clauses.addBinary(literals[0], literals[1]);
            return;
        }

        // normal clause
        var clause = try self.clauses.addClause(literals);
        try self.watch.append(clause, [_]Literal{ literals[0], literals[1] });
    }

    fn setUnits(self: *Self) !void {
        for (self.units) |to_set| {
            if (!try self.set(
                to_set.variable,
                if (to_set.is_negated)
                    .FORCE_FALSE
                else
                    .FORCE_TRUE,
            )) {
                // in this case there was a conflict
            }
        }
    }

    fn isTrue(self: Self, literal: Literal) bool {
        return literal.is_negated != self.variables[literal.variable].isTrue();
    }

    fn unassigned(self: Self, literal: Literal) bool {
        return self.variables[literal.variable] == .UNASSIGNED;
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

    pub fn deinit(self: *SatInstance) void {
        self.binary_clauses.deinit();
        self.clauses.deinit();
        self.setting_order.deinit();
        self.units.deinit();
        self.allocator.free(self.variables);
        self.watch.deinit();
    }
};
