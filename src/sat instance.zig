const std = @import("std");
const Allocator = std.mem.Allocator;

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
        while (true) {

            // eliminate the pure literals
            // all the literals that come up with only one polarity, can be set such that their clauses
            // are all made true
            // try self.eliminatePureLiterals();

            // find unary clauses and propagate
            // if the return value is false there was a collision
            //if (!try self.propagateUnaries()) {
            // try to resolve the problems
            // if not able to resolve the instance was no solvable
            //    if (!self.resolve()) {
            //        std.debug.print("unaries\n", .{});
            //        return SatResult{ .UNSAT = true };
            //    }
            //}

            // check if every variable was already set
            if (self.setting_order.items.len == self.variables.len) {
                if (self.verify()) {
                    return SatResult{ .SAT = self.variables };
                } else if (!self.resolve()) {
                    std.debug.print("verify\n", .{});
                    return SatResult{ .UNSAT = true };
                }
            }

            // if this is not the case pick the next variable to set
            try self.chooseLiteral();
        }

        return SatResult{ .UNSAT = true };
    }

    fn verify(self: Self) bool {
        for (self.clauses.items) |clause| {
            var found_one: bool = false;
            for (clause.literals.items) |literal| {
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

    fn chooseLiteral(self: *Self) !void {
        var best_var: usize = 0;
        var best_count: usize = 0;
        var best_positive: usize = 0;
        var found_literal = false;

        for (self.variables, 0..) |variable, i| {
            if (variable != .UNASSIGNED) {
                continue;
            }

            if (best_count == 0) {
                best_var = i;
                found_literal = true;
            }

            var literal_count: usize = 0;
            var positive_literals: usize = 0;
            for (self.clauses.items) |clause| {
                if (!clause.isEmptyClause(self.variables)) {
                    for (clause.literals.items) |item| {
                        if (item.variable == i) {
                            literal_count += 1;

                            if (!item.is_negated) {
                                positive_literals += 1;
                            }
                        }
                    }
                }
            }

            if (literal_count > best_count or literal_count == best_count and
                max_pos_neg(literal_count, positive_literals) > max_pos_neg(best_count, best_positive))
            {
                best_var = i;
                best_count = literal_count;
                best_positive = positive_literals;
            }
        }

        if (found_literal) {
            self.variables[best_var] = if (max_pos_neg(best_count, best_positive) == best_positive)
                .TEST_TRUE
            else
                .TEST_FALSE;

            std.debug.print("choose {d} to be {s}\n", .{ best_var + 1, self.variables[best_var].toString() });
            try self.setting_order.append(best_var);
        }
    }

    fn max_pos_neg(count: usize, pos: usize) usize {
        return if (pos > count / 2)
            pos
        else
            count - pos;
    }

    fn eliminatePureLiterals(self: *Self) !void {
        for (self.variables, 0..) |variable, i| {
            if (variable != .UNASSIGNED) {
                continue;
            }

            var polarity: ?bool = null;
            var is_pure = true;
            outer: for (self.clauses.items) |clause| {
                // do not waste time on empty clauses
                if (!clause.isEmptyClause(self.variables)) {

                    // look for our variable
                    for (clause.literals.items) |item| {

                        // check if we found it
                        if (item.variable == i) {

                            // verify if it is pure
                            if (polarity) |value| {
                                if (value != item.is_negated) {
                                    is_pure = false;
                                    break :outer;
                                }
                            } else {
                                polarity = item.is_negated;
                            }
                        }
                    }
                }
            }

            if (is_pure) {
                self.variables[i] = if (polarity orelse false)
                    .FORCE_TRUE
                else
                    // potentially the case the variable is unassigned but not needed
                    // this case would also be covered by this branch
                    .FORCE_FALSE;

                try self.setting_order.append(i);
            }
        }
    }

    fn resolve(self: *Self) bool {
        while (true) {
            var lastSet = self.setting_order.getLastOrNull();

            if (lastSet) |value| {
                var variable = &self.variables[value];

                if (variable.isForce()) {
                    std.debug.print("{d} cannot be\n", .{value + 1});
                    variable.* = .UNASSIGNED;
                    _ = self.setting_order.pop();
                } else {
                    variable.setInverse();
                    std.debug.print("{d} is {s} now\n", .{ value + 1, variable.toString() });
                    return true;
                }
            } else {
                return false;
            }
        }
    }

    fn propagateUnaries(self: *Self) !bool {
        var vars_to_set = std.ArrayList(Literal).init(self.allocator);
        var var_arg: Literal = undefined;

        while (true) {
            // find the variables to set
            for (self.clauses.items) |clause| {
                if (clause.isUnitClause(self.variables, &var_arg)) {
                    try vars_to_set.append(var_arg);
                }
            }

            if (vars_to_set.items.len == 0) {
                return true;
            }

            // set the variables
            for (vars_to_set.items) |literal| {
                var value = if (literal.is_negated)
                    Variable.FORCE_FALSE
                else
                    Variable.FORCE_TRUE;

                if (self.variables[literal.variable] == Variable.UNASSIGNED) {
                    try self.setting_order.append(literal.variable);
                    self.variables[literal.variable] = value;
                } else if (!self.variables[literal.variable].isEqual(value)) {
                    // there was a collision
                    return false;
                }
            }

            vars_to_set.clearRetainingCapacity();
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

pub const PossibleResults = enum {
    UNSAT,
    SAT,
};

pub const SatResult = union(PossibleResults) {
    UNSAT: bool,
    SAT: []Variable,

    const Self = @This();

    pub fn toString(self: Self) [:0]const u8 {
        return switch (self) {
            .SAT => "SATISFIABLE",
            .UNSAT => "UNSATISFIABLE",
        };
    }

    pub fn format(
        self: Self,
        comptime fmt: []const u8,
        options: std.fmt.FormatOptions,
        writer: anytype,
    ) !void {
        _ = options;
        _ = fmt;

        switch (self) {
            .SAT => |solution| {
                for (solution, 1..) |var_state, var_num| {
                    if (var_num != 1) {
                        try writer.print(" ", .{});
                    }

                    try writer.print("{s}{}", .{ var_state, var_num });
                }
            },
            .UNSAT => {},
        }
    }
};

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

pub const Variable = enum(i8) {
    UNASSIGNED = -1,
    TEST_FALSE,
    TEST_TRUE,
    FORCE_FALSE,
    FORCE_TRUE,

    const Self = @This();

    pub fn isForce(self: Self) bool {
        return self == .FORCE_FALSE or self == .FORCE_TRUE;
    }

    pub fn isTrue(self: Self) bool {
        return self == .TEST_FALSE or self == .FORCE_TRUE;
    }

    pub fn isEqual(self: Self, other: Self) bool {
        const self_true = self.isTrue();
        const other_true = other.isForce();

        return self_true and other_true or !self_true and !other_true;
    }

    pub fn setInverse(self: *Self) void {
        self.* = switch (self.*) {
            .TEST_FALSE => .FORCE_TRUE,
            .TEST_TRUE => .FORCE_FALSE,
            .FORCE_FALSE => .TEST_TRUE,
            .FORCE_TRUE => .TEST_FALSE,
            else => .UNASSIGNED,
        };
    }

    pub fn toString(self: Self) []const u8 {
        return switch (self) {
            .TEST_TRUE => "TEST_TRUE",
            .TEST_FALSE => "TEST_FALSE",
            .FORCE_TRUE => "FORCE_TRUE",
            .FORCE_FALSE => "FORCE_FALSE",
            else => "UNASSIGNED",
        };
    }

    pub fn format(
        self: Self,
        comptime fmt: []const u8,
        options: std.fmt.FormatOptions,
        writer: anytype,
    ) !void {
        _ = options;
        _ = fmt;

        if (!self.isTrue()) {
            try writer.print("-", .{});
        }
    }
};

pub const Literal = struct {
    is_negated: bool,
    variable: u31,

    const Self = @This();

    pub fn format(
        self: Self,
        comptime fmt: []const u8,
        options: std.fmt.FormatOptions,
        writer: anytype,
    ) !void {
        _ = options;
        _ = fmt;

        const sign = if (self.is_negated) "-" else "";

        try writer.print("{s}{}", .{ sign, self.variable + 1 });
    }
};
