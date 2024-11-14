const std = @import("std");
const assert = std.debug.assert;
const Allocator = std.mem.Allocator;
const Variable = @import("variable.zig").Variable;
const Clause = @import("clause.zig").Clause;
const ClauseDb = @import("clause_db.zig");
const SatResult = @import("result.zig").SatResult;
const Literal = @import("literal.zig").Literal;
const BinClauses = @import("binary_clauses.zig").BinClauses;
const WatchList = @import("watch.zig").WatchList;
const ClauseRef = @import("clause.zig").ClauseRef;
const Impls = @import("impl.zig").Impls;
const Impl = @import("impl.zig").Impl;
const Reason = @import("impl.zig").Reason;
const Conflict = @import("impl.zig").Conflict;
const UnitSetting = @import("watch.zig").UnitSetting;
const ImplGraphWriter = @import("impl_graph_writer.zig");
const ClauseLearner = @import("clause_learner.zig");
const Chooser = @import("chooser.zig");
const ClauseHeuristic = @import("clause.zig").ClauseHeuristic;
const ClauseTier = @import("mem_cell.zig").ClauseTier;

var flag = false;

pub const SatInstance = struct {
    allocator: Allocator,
    clauses: ClauseDb,
    binary_clauses: BinClauses,
    watch: WatchList,
    variables: Impls,
    chooser: Chooser,
    choice_count: usize = 0,
    setting_order: std.ArrayList(usize),
    units_to_set: std.ArrayList(UnitSetting),
    learner: ClauseLearner,
    heuristic: ClauseHeuristic,
    conflicts: usize = 0,

    const Self = @This();

    pub fn init(
        allocator: Allocator,
        variables: usize,
    ) !SatInstance {
        var setting_order = std.ArrayList(usize).init(allocator);
        try setting_order.ensureTotalCapacity(variables);
        return .{
            .allocator = allocator,
            .setting_order = setting_order,
            .watch = try WatchList.init(variables, allocator),
            .chooser = try Chooser.init(allocator, variables),
            .variables = try Impls.init(allocator, variables),
            .clauses = try ClauseDb.init(allocator, variables),
            .learner = try ClauseLearner.init(allocator, variables),
            .units_to_set = std.ArrayList(UnitSetting).init(allocator),
            .heuristic = try ClauseHeuristic.init(allocator, variables),
            .binary_clauses = try BinClauses.init(allocator, variables),
        };
    }

    pub fn solve(self: *Self) !SatResult {
        self.conflicts = 0;

        while (true) {
            while (self.units_to_set.items.len > 0) {
                const conflict = try self.setUnits();
                if (conflict) |c| if (!try self.resolve(c)) return .unsat;
            }

            // if the variable were all set without a conflict
            // we have found a sitisfying result
            if (self.setting_order.items.len == self.variables.impls.len) {
                assert(self.isSat());
                return .{ .sat = self.variables };
            }

            const conflict = try self.choose();
            if (conflict) |c| if (!try self.resolve(c)) return .unsat;
        }
    }

    /// set `variable` to `state`.
    pub fn set(self: *Self, variable: usize, state: Variable, reason: Reason) !?Conflict {
        assert(!state.unassigned());

        const var_ptr = self.variables.getVar(variable);
        if (var_ptr.* == state) return null;
        assert(var_ptr.unassigned());
        switch (reason) {
            .unary, .binary => {},
            .other => |clause| clause.setUsed(self.clauses, true),
        }

        self.variables.set(variable, state, reason, self.choice_count);
        try self.setting_order.append(variable);
        return try self.watch.set(Literal.init(state == .neg, @intCast(variable)), self);
    }

    pub fn addUnit(self: *Self, unit: UnitSetting) !void {
        assert(unit.to_set.isGood(self.variables));

        if (!self.isTrue(unit.to_set)) try self.units_to_set.append(unit);
    }

    pub fn clauseCount(self: Self) usize {
        return self.binary_clauses.len + self.clauses.getLength();
    }

    /// adds a clause to this sat instance
    pub fn addClause(self: *Self, literals: []Literal, lbd: u16) !void {
        // append a unit clause
        if (literals.len == 1) {
            try self.addUnit(.{ .to_set = literals[0], .reason = .unary });
            assert(lbd <= 1);
            return;
        }

        // binary clause
        if (literals.len == 2) {
            try self.binary_clauses.addBinary(literals[0], literals[1]);
            assert(lbd <= 2);
            return;
        }

        // normal clause
        _ = try self.clauses.addClause(literals, lbd, &self.watch);
    }

    /// this is a debugging method!
    ///
    /// it checks that `literal` is in a unit assignement
    pub fn isUnitAssignement(self: Self, literal: Literal) bool {
        for (self.units_to_set.items) |unit| {
            if (unit.to_set.eql(literal)) return true;
        }

        return false;
    }

    /// checks if the instance is currently satisfied
    fn isSat(self: Self) bool {
        for (self.watch.watches) |watches| {
            for (watches.items) |watch| {
                if (!watch.clause.isSatisfied(self)) return false;
            }
        }

        return true;
    }

    /// set all the unit clauses
    fn setUnits(self: *Self) !?Conflict {
        while (self.units_to_set.popOrNull()) |to_set| {
            if (try self.set(
                to_set.to_set.variable,
                if (to_set.to_set.is_negated) .neg else .pos,
                to_set.reason,
            )) |conflict| return conflict;

            // now that the variable was set check implications
            for (self.binary_clauses.getImplied(to_set.to_set)) |to_add| {
                // if the literal is false we have a conflict
                if (self.isFalse(to_add)) return .{
                    .binary = .{ to_set.to_set.negated(), to_add },
                };

                if (self.isTrue(to_add)) continue;
                try self.addUnit(.{
                    .to_set = to_add,
                    .reason = .{ .binary = to_set.to_set },
                });
            }
        }

        // we managed to go through unit propagation without a conflict
        // => the unit list should be empty
        assert(self.units_to_set.items.len == 0);

        return null;
    }

    /// choose using Evsids and Phase Saving
    fn choose(self: *Self) !?Conflict {
        assert(self.units_to_set.items.len == 0);

        while (self.chooser.nextVar()) |variable| {
            const value = self.variables.get(variable).variable;
            if (!value.unassigned()) continue;

            self.choice_count += 1;
            const new_val = value.toggleAssign();
            assert(!new_val.unassigned());
            return try self.set(variable, new_val, .unary);
        }

        assert(self.chooser.len() == 0);
        assert(self.setting_order.items.len == self.variables.impls.len);
        return null;
    }

    /// a trivial chooser that always takes the first unassinged variable
    fn chooseTrivial(self: *Self) !?Conflict {
        assert(self.units_to_set.items.len == 0);

        for (self.variables.impls, 0..) |v, i| {
            if (!v.variable.unassigned()) continue;

            // as there is no reason the reason and
            // it is a test assignement choose any literal
            self.choice_count += 1;
            return try self.set(i, .pos, .unary);
        }

        // should not arrise
        unreachable;
    }

    /// the method used to resolve a conflict in the assignement
    /// (basic backtracking).
    ///
    /// iff returns true the backtracking was successful
    fn resolve(self: *Self, conflict: Conflict) !bool {
        self.conflicts += 1;
        try self.heuristic.conflict(&self.clauses, &self.watch);

        // the current unit clauses did lead to a problem
        self.units_to_set.clearRetainingCapacity();

        const backtack_place = try self.learner.learn(conflict, self);
        const learned = self.learner.literals.items;
        const learned_glue = if (learned.len < 3)
            0
        else
            self.heuristic.computeGlue(self.*, learned);

        try self.backtrack(backtack_place);

        if (flag) {
            std.debug.print("appending: {{ ", .{});
            for (learned) |lit| std.debug.print("{s}, ", .{lit});
            std.debug.print("}}\n", .{});
        }

        const lbd: u16 = undefined;

        const reason: Reason = switch (learned.len) {
            0 => return false,
            1 => .unary,
            2 => blk: {
                try self.addClause(learned, 0);
                break :blk .{ .binary = learned[1] };
            },
            else => blk: {
                const clause = try self.clauses.addClause(learned, lbd, &self.watch);
                clause.setLbd(self.clauses, learned_glue);
                clause.setTier(self.clauses, ClauseTier.fromLbd(learned_glue));
                break :blk .{ .other = clause };
            },
        };

        self.learner.clear();
        try self.units_to_set.append(.{ .reason = reason, .to_set = learned[0] });
        return true;
    }

    fn backtrack(self: *SatInstance, to: usize) !void {
        if (self.choice_count <= to) return;
        self.choice_count = to;

        while (self.setting_order.getLastOrNull()) |value| {
            const variable = self.variables.get(value);
            if (variable.choice_count == to) break;

            // makes the variable unassigned but keeps it`s fase
            variable.invalidate();
            try self.chooser.append(@intCast(value));
            _ = self.setting_order.pop();

            switch (variable.reason) {
                .unary, .binary => {},
                .other => |clause| {
                    const lits = clause.getLiterals(self.clauses);
                    const glue = self.heuristic.computeGlue(self.*, lits);
                    const curr_glue = clause.getLbd(self.clauses);
                    if (curr_glue <= glue) continue;
                    clause.setLbd(self.clauses, curr_glue);
                    clause.setTier(self.clauses, ClauseTier.fromLbd(curr_glue));
                    clause.setConflict(self.clauses, true);
                    clause.setUsed(self.clauses, false);
                },
            }
        }
    }

    pub fn debugSettingOrder(self: Self) void {
        std.debug.print("{{ ", .{});
        if (self.setting_order.items.len >= 1) {
            const first = self.setting_order.items[0];
            std.debug.print("{s}{d}", .{ self.variables.getVar(first), first + 1 });
            for (self.setting_order.items[1..]) |next| {
                std.debug.print(", {s}{d}", .{ self.variables.getVar(next), next + 1 });
            }
        }
        std.debug.print(" }}\n", .{});
    }

    pub fn isTrue(self: Self, literal: Literal) bool {
        assert(literal.variable < self.variables.impls.len);
        const val = self.variables.getFromLit(literal).*;
        return !val.unassigned() and literal.is_negated == (val == .neg);
    }

    pub fn isFalse(self: Self, literal: Literal) bool {
        assert(literal.variable < self.variables.impls.len);
        const val = self.variables.getFromLit(literal).*;
        return !val.unassigned() and literal.is_negated == (val == .pos);
    }

    pub fn unassigned(self: Self, literal: Literal) bool {
        assert(literal.variable < self.variables.impls.len);
        return self.variables.getFromLit(literal).unassigned();
    }

    pub fn format(
        self: Self,
        comptime _: []const u8,
        _: std.fmt.FormatOptions,
        writer: anytype,
    ) !void {
        const clauses = self.clauses.clauses.items;
        if (clauses.len >= 1) {
            try writer.print("({s})", .{clauses[0].getRef(&self.clauses)});

            for (clauses[1..]) |clause| {
                try writer.print(" & ({s})", .{clause.getRef(&self.clauses)});
            }
        }

        if (self.binary_clauses.len == 0) return;
        try writer.print("\n{s}", .{self.binary_clauses});
    }

    pub fn deinit(self: *SatInstance) void {
        self.heuristic.deinit(self.allocator);
        self.allocator.free(self.variables);
        self.binary_clauses.deinit();
        self.setting_order.deinit();
        self.clauses.deinit();
        self.chooser.deinit();
        self.learner.deinit();
        self.units.deinit();
        self.watch.deinit();
    }
};

test {
    _ = @import("variable.zig");
    _ = @import("clause.zig");
    _ = @import("clause_db.zig");
    _ = @import("result.zig");
    _ = @import("literal.zig");
    _ = @import("binary_clauses.zig");
    _ = @import("watch.zig");
    _ = @import("clause.zig");
    _ = @import("impl.zig");
    _ = @import("watch.zig");
    _ = @import("impl_graph_writer.zig");
    _ = @import("clause_learner.zig");
    _ = @import("chooser.zig");
}
