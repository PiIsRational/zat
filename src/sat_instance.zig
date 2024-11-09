const std = @import("std");
const assert = std.debug.assert;
const Allocator = std.mem.Allocator;
const Variable = @import("variable.zig").Variable;
const Clause = @import("clause.zig").Clause;
const ClauseDb = @import("clause_db.zig").ClauseDb;
const SatResult = @import("result.zig").SatResult;
const Literal = @import("literal.zig").Literal;
const BinClauses = @import("binary_clauses.zig").BinClauses;
const WatchList = @import("watch.zig").WatchList;
const ClauseRef = @import("clause.zig").ClauseRef;
const Impls = @import("impl.zig").Impls;
const Reason = @import("impl.zig").Reason;
const Conflict = @import("impl.zig").Conflict;
const UnitSetting = @import("watch.zig").UnitSetting;
const ImplGraphWriter = @import("impl_graph_writer.zig");

var flag = false;

pub const SatInstance = struct {
    allocator: Allocator,
    clauses: ClauseDb,
    binary_clauses: BinClauses,
    watch: WatchList,
    variables: Impls,
    setting_order: std.ArrayList(usize),
    units_to_set: std.ArrayList(UnitSetting),

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
            .clauses = try ClauseDb.init(allocator, variables),
            .watch = try WatchList.init(variables, allocator),
            .variables = try Impls.init(allocator, variables),
            .units_to_set = std.ArrayList(UnitSetting).init(allocator),
            .binary_clauses = try BinClauses.init(allocator, variables),
        };
    }

    pub fn solve(self: *Self) !SatResult {
        while (true) {
            // first resolve unit clauses
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

            // choose a variable to set
            const conflict = try self.choose();
            if (conflict) |c| if (!try self.resolve(c)) return .unsat;
        }
    }

    /// set `variable` to `state`.
    pub fn set(self: *Self, variable: usize, state: Variable, reason: Reason) !?Conflict {
        // cannot set a variable to unassigned
        assert(state != .unassigned);

        const var_ptr = self.variables.getVar(variable);

        if (var_ptr.isEqual(state)) return null;
        assert(var_ptr.* == .unassigned);

        self.variables.set(variable, state, reason);
        try self.setting_order.append(variable);
        return try self.watch.set(Literal.init(
            state.isFalse(),
            @intCast(variable),
        ), self);
    }

    pub fn addUnit(self: *Self, unit: UnitSetting) !void {
        assert(unit.to_set.isGood(self.variables));

        if (!self.isTrue(unit.to_set)) try self.units_to_set.append(unit);
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
            try self.addUnit(.{ .to_set = literals[0], .reason = .unary });
            return;
        }

        // binary clause
        if (literals.len == 2) {
            try self.binary_clauses.addBinary(literals[0], literals[1]);
            return;
        }

        // normal clause
        const c = try self.clauses.addClause(literals);
        try self.watch.append(c, .{ literals[0], literals[1] });
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

    /// this is a debugging method!
    ///
    /// it checks that `literal` is the last chosen assignement
    pub fn isLastChoice(self: Self, literal: Literal) bool {
        var i = self.setting_order.items.len;
        while (i > 0) : (i -= 1) {
            const current = self.setting_order.items[i - 1];
            if (!self.variables.getVar(current).isForce() and
                current == literal.variable and
                self.variables.getVar(current).isFalse() == literal.is_negated)
            {
                return true;
            }
        }

        return false;
    }

    /// checks if the instance is currently satisfied
    fn isSat(self: Self) bool {
        for (self.clauses.clauses.items) |c| {
            if (!c.isSatisfied(self)) return false;
        }

        return true;
    }

    /// set all the unit clauses
    fn setUnits(self: *Self) !?Conflict {
        while (self.units_to_set.popOrNull()) |to_set| {
            if (try self.set(
                to_set.to_set.variable,
                if (to_set.to_set.is_negated) .force_false else .force_true,
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

    /// choose the next literal to pick and set it
    fn choose(self: *Self) !?Conflict {
        assert(self.units_to_set.items.len == 0);

        // TODO: implement proper heuristics to make this work
        for (self.variables.impls, 0..) |v, i| {
            if (v.variable != .unassigned) continue;

            // as there is no reason the reason and
            // it is a test assignement choose any literal
            return try self.set(i, .test_true, .unary);
        }

        return null;
    }

    /// the method used to resolve a conflict in the assignement
    /// (basic backtracking).
    ///
    /// iff returns true the backtracking was successful
    fn resolve(self: *Self, conflict: Conflict) !bool {
        // the current unit clauses did lead to a problem
        self.units_to_set.clearRetainingCapacity();

        if (flag) {
            const writer = ImplGraphWriter.init(self.*, conflict);
            std.debug.print("{s}\n", .{writer});
            unreachable;
        }

        var i: usize = 0;
        while (self.setting_order.popOrNull()) |value| {
            i += 1;
            var variable = self.variables.getVar(value);

            if (!variable.isForce()) {
                const new_state = variable.getInverse();
                assert(new_state.isForce());

                variable.* = .unassigned;
                if (try self.set(value, new_state, .unary) != null) continue;

                return true;
            }

            variable.* = .unassigned;
        }

        // the instance is unsat as the variable could not be found
        return false;
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

        return !self.unassigned(literal) and
            literal.is_negated == self.variables.getFromLit(literal).isFalse();
    }

    pub fn isFalse(self: Self, literal: Literal) bool {
        assert(literal.variable < self.variables.impls.len);

        return !self.unassigned(literal) and
            literal.is_negated == self.variables.getFromLit(literal).isTrue();
    }

    pub fn unassigned(self: Self, literal: Literal) bool {
        assert(literal.variable < self.variables.impls.len);

        return self.variables.getFromLit(literal).* == .unassigned;
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
        self.binary_clauses.deinit();
        self.clauses.deinit();
        self.setting_order.deinit();
        self.units.deinit();
        self.allocator.free(self.variables);
        self.watch.deinit();
    }
};
