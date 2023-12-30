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
        // first resolve unit clauses
        if (self.setUnits()) {
            if (!self.resolve()) {
                return SatResult{
                    .UNSAT = false,
                };
            }
        }

        // if the variable were all set without a conflict
        // we have found a sitisfying result
        if (self.setting_order.items.len == self.variables.len) {
            return SatResult{
                .SAT = self.variables,
            };
        }

        // choose a variable to set
        if (self.choose()) {
            if (!self.resolve()) {
                return SatResult{
                    .UNSAT = false,
                };
            }
        }
    }

    /// set `variable` to `state`.
    ///
    /// iff was able to set returns true
    pub fn set(self: *Self, variable: usize, state: Variable) !bool {
        // cannot set a variable to unassigned
        std.debug.assert(state != .UNASSIGNED);

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
            try self.units.append(literals[1]);
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

    /// set all the unit clauses
    ///
    /// returns true iff there was a conflict
    fn setUnits(self: *Self) !bool {
        for (self.units.items) |to_set| {
            if (!try self.set(
                to_set.variable,
                if (to_set.is_negated)
                    .FORCE_FALSE
                else
                    .FORCE_TRUE,
            )) {
                // in this case there was a conflict
                return true;
            }

            // now that the variable was set check implications
            for (self.binary_clauses.getImplied(to_set)) |to_add| {
                if (!self.isFalse(to_add)) {
                    self.units.append(to_add);
                } else {
                    // if the literal is false we have a conflict
                    return true;
                }
            }
        }

        // we managed to go through unit propagation without a conflict
        // -> the unit list can be cleared
        self.units.clearRetainingCapacity();

        return false;
    }

    fn choose(self: *Self) bool {
        _ = self;
        return true;
    }

    /// the method used to resolve a conflict in the assignement
    /// (basic backtracking).
    ///
    /// iff returns true the backtracking was successful
    fn resolve(self: *Self) bool {
        while (self.setting_order.popOrNull()) |value| {
            var variable = &self.variables[value];
            if (!variable.isForce()) {
                variable.setInverse();

                // the current unit clauses lead to a problem
                // so the assignements are all deleted
                self.units.clearRetainingCapacity();
                return true;
            }

            variable.* = .UNASSIGNED;
        }

        // the instance is unsat as the variable could not be found
        return false;
    }

    pub fn isTrue(self: Self, literal: Literal) bool {
        return !self.unassigned(literal) and
            literal.is_negated == self.variables[literal.variable].isFalse();
    }

    pub fn isFalse(self: Self, literal: Literal) bool {
        return !self.unassigned(literal) and
            literal.is_negated == self.variables[literal.variable].isTrue();
    }

    pub fn unassigned(self: Self, literal: Literal) bool {
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

            try writer.print("({s})", .{clause.getRef(&self.clauses)});
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
