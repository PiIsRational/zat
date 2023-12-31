const std = @import("std");
const assert = std.debug.assert;
const Allocator = std.mem.Allocator;
const Variable = @import("variable.zig").Variable;
const Clause = @import("clause.zig").Clause;
const ClauseDb = @import("clause db.zig").ClauseDb;
const SatResult = @import("result.zig").SatResult;
const Literal = @import("literal.zig").Literal;
const BinClauses = @import("binary clauses.zig").BinClauses;
const WatchList = @import("watch.zig").WatchList;
const ClauseRef = @import("clause.zig").ClauseRef;

pub const SatInstance = struct {
    allocator: Allocator,
    clauses: ClauseDb,
    binary_clauses: BinClauses,
    watch: WatchList,
    variables: []Variable,
    setting_order: std.ArrayList(usize),
    units_to_set: std.ArrayList(Literal),
    debug: bool,

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
            .units_to_set = std.ArrayList(Literal).init(allocator),
            .debug = false,
        };
    }

    pub fn solve(self: *Self) !SatResult {
        while (true) {
            if (self.debug) {
                //if (self.units_to_set.items.len == 1 and self.units_to_set.items[0].eql(Literal.init(false, 16))) {
                std.debug.print("state {s}\n", .{SatResult{ .SAT = self.variables }});
                if (self.setting_order.items.len > 0) {
                    std.debug.print("choose: {s}{}\n", .{ self.variables[self.setting_order.getLast()], self.setting_order.getLast() + 1 });
                }
                std.debug.print("propagate: ({s})\n", .{ClauseRef{ .lits = self.units_to_set.items }});
                self.debug = true;
            }
            self.debug = false;

            // first resolve unit clauses
            if (try self.setUnits()) {
                if (!try self.resolve()) {
                    return SatResult.UNSAT;
                }
            }

            // if the variable were all set without a conflict
            // we have found a sitisfying result
            if (self.setting_order.items.len == self.variables.len) {
                assert(self.isSat());

                return SatResult{ .SAT = self.variables };
            }

            // choose a variable to set
            if (try self.choose()) {
                if (!try self.resolve()) {
                    return SatResult.UNSAT;
                }
            }
        }
    }

    /// set `variable` to `state`.
    ///
    /// iff was able to set returns true
    pub fn set(self: *Self, variable: usize, state: Variable) !bool {
        if ((variable == 3 or variable == 12 or variable == 8) and state.isTrue() and state != .UNASSIGNED) {
            self.debug = true;
        }

        // cannot set a variable to unassigned
        assert(state != .UNASSIGNED);

        if (self.variables[variable].isEqual(state)) {
            if (self.debug) {
                std.debug.print("already set {s}{}\n", .{ state, variable + 1 });
            }
            return true;
        }

        if (self.variables[variable] != .UNASSIGNED) {
            if (self.debug) {
                std.debug.print("{s}{} is not unassigned\n", .{ state, variable + 1 });
            }
            return false;
        }

        self.variables[variable] = state;
        try self.setting_order.append(variable);
        return !try self.watch.set(Literal.init(
            state.isFalse(),
            @intCast(variable),
        ), self);
    }

    pub fn addUnit(self: *Self, unit: Literal) !void {
        assert(!unit.is_garbage);
        assert(unit.variable < self.variables.len);

        if (!self.isTrue(unit)) {
            try self.units_to_set.append(unit);
        }
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
            try self.addUnit(literals[0]);
            return;
        }

        // binary clause
        if (literals.len == 2) {
            try self.binary_clauses.addBinary(literals[0], literals[1]);
            return;
        }

        // normal clause
        var c = try self.clauses.addClause(literals);
        try self.watch.append(c, [_]Literal{ literals[0], literals[1] });
    }

    /// checks if the instance is currently satisfied
    fn isSat(self: *Self) bool {
        for (self.clauses.clauses.items) |c| {
            if (!c.isSatisfied(self)) {
                std.debug.print("({s}) is unsat\n", .{c.getRef(&self.clauses)});
                return false;
            }
        }

        return true;
    }

    /// set all the unit clauses
    ///
    /// returns true iff there was a conflict
    fn setUnits(self: *Self) !bool {
        while (self.units_to_set.popOrNull()) |to_set| {
            if (self.debug) {
                std.debug.print("v\t{s}\to ({s})\n", .{ to_set, ClauseRef{ .lits = self.units_to_set.items } });
            }
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
                if (self.isFalse(to_add)) {
                    // if the literal is false we have a conflict
                    return true;
                }

                if (self.unassigned(to_add)) {
                    try self.addUnit(to_add);
                }
            }
            if (self.debug) {
                std.debug.print("\t\to ({s})\n", .{ClauseRef{ .lits = self.units_to_set.items }});
            }
        }

        // we managed to go through unit propagation without a conflict
        // => the unit list should be empty
        assert(self.units_to_set.items.len == 0);

        return false;
    }

    /// choose the next literal to pick and set it
    ///
    /// iff encountered an error returns true
    fn choose(self: *Self) !bool {
        // TODO: implement proper heuristics to make this work
        for (self.variables, 0..) |v, i| {
            if (v == .UNASSIGNED) {
                return !try self.set(i, .TEST_TRUE);
            }
        }

        return true;
    }

    /// the method used to resolve a conflict in the assignement
    /// (basic backtracking).
    ///
    /// iff returns true the backtracking was successful
    fn resolve(self: *Self) !bool {
        // the current unit clauses did lead to a problem
        self.units_to_set.clearRetainingCapacity();

        while (self.setting_order.popOrNull()) |value| {
            var variable = &self.variables[value];

            if (!variable.isForce()) {
                const new_state = variable.getInverse();
                assert(new_state.isForce());

                variable.* = .UNASSIGNED;
                if (!try self.set(value, new_state)) {
                    continue;
                }

                return true;
            }

            variable.* = .UNASSIGNED;
        }

        // the instance is unsat as the variable could not be found
        return false;
    }

    pub fn isTrue(self: Self, literal: Literal) bool {
        assert(literal.variable < self.variables.len);

        return !self.unassigned(literal) and
            literal.is_negated == self.variables[literal.variable].isFalse();
    }

    pub fn isFalse(self: Self, literal: Literal) bool {
        assert(literal.variable < self.variables.len);

        return !self.unassigned(literal) and
            literal.is_negated == self.variables[literal.variable].isTrue();
    }

    pub fn unassigned(self: Self, literal: Literal) bool {
        assert(literal.variable < self.variables.len);

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
