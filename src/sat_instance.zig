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
const UnitSetting = @import("watch.zig").UnitSetting;

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
        return .{
            .allocator = allocator,
            .clauses = try ClauseDb.init(allocator, variables),
            .binary_clauses = try BinClauses.init(allocator, variables),
            .watch = try WatchList.init(variables, allocator),
            .variables = try Impls.init(allocator, variables),
            .setting_order = std.ArrayList(usize).init(allocator),
            .units_to_set = std.ArrayList(UnitSetting).init(allocator),
        };
    }

    pub fn solve(self: *Self) !SatResult {
        while (true) {
            // first resolve unit clauses
            while (self.units_to_set.items.len > 0) {
                if (try self.setUnits() and !try self.resolve()) return .UNSAT;
            }

            // if the variable were all set without a conflict
            // we have found a sitisfying result
            if (self.setting_order.items.len == self.variables.impls.len) {
                assert(self.isSat());
                return .{ .SAT = self.variables };
            }

            // choose a variable to set
            if (try self.choose() and !try self.resolve()) return .UNSAT;
        }
    }

    /// set `variable` to `state`.
    ///
    /// iff was able to set returns true
    pub fn set(self: *Self, variable: usize, state: Variable, reason: Clause) !bool {
        // cannot set a variable to unassigned
        assert(state != .UNASSIGNED);

        const var_ptr = self.variables.getVar(variable);

        if (var_ptr.isEqual(state)) return true;
        if (var_ptr.* != .UNASSIGNED) return false;

        self.variables.set(variable, state, reason);
        try self.setting_order.append(variable);
        return !try self.watch.set(Literal.init(
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
            try self.addUnit(.{ .to_set = literals[0], .reason = Clause.getNull() });
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

    ///this is a debugging method!
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
    fn isSat(self: *Self) bool {
        for (self.clauses.clauses.items) |c| {
            if (!c.isSatisfied(self)) return false;
        }

        return true;
    }

    /// set all the unit clauses
    ///
    /// returns true iff there was a conflict
    fn setUnits(self: *Self) !bool {
        while (self.units_to_set.popOrNull()) |to_set| {
            if (!try self.set(
                to_set.to_set.variable,
                if (to_set.to_set.is_negated)
                    .FORCE_FALSE
                else
                    .FORCE_TRUE,
                to_set.reason,
            )) {
                // in this case there was a conflict
                return true;
            }

            // now that the variable was set check implications
            for (self.binary_clauses.getImplied(to_set.to_set)) |to_add| {
                // if the literal is false we have a conflict
                if (self.isFalse(to_add)) return true;

                if (!self.isTrue(to_add)) {
                    try self.addUnit(.{ .to_set = to_add, .reason = to_set.reason });
                }
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
        assert(self.units_to_set.items.len == 0);

        // TODO: implement proper heuristics to make this work
        for (self.variables.impls, 0..) |v, i| {
            if (v.variable != .UNASSIGNED) continue;

            // as there is no reason the reason and
            // it is a test assignement choose any literal
            const res = !try self.set(i, .TEST_TRUE, Clause.getNull());
            return res;
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

        var i: usize = 0;
        while (self.setting_order.popOrNull()) |value| {
            i += 1;
            var variable = self.variables.getVar(value);

            if (!variable.isForce()) {
                const new_state = variable.getInverse();
                assert(new_state.isForce());

                variable.* = .UNASSIGNED;
                // TODO: the given reason here is wrong
                // (it is set because of a conflict)
                // it should be fixed when implementing the CDCL
                if (!try self.set(value, new_state, Clause.getNull())) continue;

                return true;
            }

            variable.* = .UNASSIGNED;
        }

        // the instance is unsat as the variable could not be found
        return false;
    }

    fn debugSettingOrder(self: Self) void {
        std.debug.print("{{ ", .{});
        if (self.setting_order.items.len >= 1) {
            const first = self.setting_order.items[0];
            std.debug.print("{s}{d}", .{ self.variables.getVar(first), first });
            for (self.setting_order.items[1..]) |next| {
                std.debug.print(", {s}{d}", .{ self.variables.getVar(next), next });
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

        return self.variables.getFromLit(literal).* == .UNASSIGNED;
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
