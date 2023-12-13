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
        //while (true) {
        // eliminate the pure literals
        // all the literals that come up with only one polarity, can be set such that their clauses
        // are all made true
        try self.eliminatePureLiterals();

        // find unary clauses and propagate
        // if the return value is false there was a collision
        if (!try self.propagateUnaries()) {
            // try to resolve the problems
            // if not able to resolve the instance was no solvable
            if (!self.resolve()) {
                return SatResult{ .UNSAT = false };
            }
        }

        // check if every variable was already set
        if (self.setting_order.items.len == self.variables.len) {
            return SatResult{ .SAT = self.variables };
        }

        // if this is not the case pick the next variable to set
        try self.chooseLiteral();
        //}

        return SatResult{ .UNSAT = false };
    }

    fn chooseLiteral(self: *Self) !void {
        var best_var: usize = 0;
        var best_count: usize = 0;
        var best_positive: usize = 0;

        for (self.variables, 0..) |variable, i| {
            if (variable != .UNASSIGNED) {
                std.debug.print("{} is {s}\n", .{ i + 1, variable.toString() });
                continue;
            }

            var literal_count: usize = 0;
            var positive_literals: usize = 0;
            for (self.clauses.items) |clause| {
                if (!clause.isEmptyClause(self.variables)) {
                    for (clause.literals.items) |item| {
                        if (@abs(item) - 1 == i) {
                            literal_count += 1;

                            if (item > 0) {
                                positive_literals += 1;
                            }
                        }
                    }
                }
            }

            std.debug.print("lit {}, pos {}, lit b {}, pos b {}\n", .{ literal_count, positive_literals, best_count, best_positive });
            if (literal_count > best_count or literal_count == best_count and
                max_pos_neg(literal_count, positive_literals) > max_pos_neg(best_count, best_positive))
            {
                best_var = i;
                best_count = literal_count;
                best_positive = positive_literals;
            }
        }

        self.variables[best_var] = if (max_pos_neg(best_count, best_positive) == best_positive)
            .TEST_TRUE
        else
            .TEST_FALSE;

        try self.setting_order.append(best_var);

        std.debug.print("t assign {s}{}\n", .{ self.variables[best_var], best_var + 1 });
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

            var polarity: isize = 0;
            var is_pure = true;
            outer: for (self.clauses.items) |clause| {
                // do not waste time on empty clauses
                if (!clause.isEmptyClause(self.variables)) {

                    // look for our variable
                    for (clause.literals.items) |item| {

                        // check if we found it
                        if (@abs(item) - 1 == i) {

                            // verify if it is pure
                            if (polarity == 0) {
                                polarity = item;
                            } else if (polarity != item) {
                                is_pure = false;
                                break :outer;
                            }
                        }
                    }
                }
            }

            if (is_pure) {
                self.variables[i] = if (polarity > 0)
                    .FORCE_TRUE
                else
                    // potentially the case the variable is unassigned but not needed
                    // this case would also be covered by this branch
                    .FORCE_FALSE;

                std.debug.print("f assign ll {s}{}\n", .{ self.variables[i], i + 1 });
                try self.setting_order.append(i);
            }
        }
    }

    fn resolve(self: *Self) bool {
        while (true) {
            var lastSet = self.getLastSet();

            if (lastSet) |value| {
                var variable = &self.variables[value];

                if (variable.*.isForce()) {
                    std.debug.print("unassign {d}\n", .{value});
                    variable.* = .UNASSIGNED;
                    _ = self.setting_order.pop();
                } else {
                    std.debug.print("invert {d}\n", .{value});
                    variable.*.setInverse();
                    return true;
                }
            } else {
                return false;
            }
        }
    }

    fn propagateUnaries(self: *Self) !bool {
        var vars_to_set = std.ArrayList(i32).init(self.allocator);
        var var_arg: i32 = undefined;

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
            for (vars_to_set.items) |variable| {
                var v: usize = @abs(variable) - 1;
                var value = if (variable < 0)
                    Variable.FORCE_FALSE
                else
                    Variable.FORCE_TRUE;

                if (self.variables[v] == Variable.UNASSIGNED) {
                    try self.setting_order.append(v);
                    self.variables[v] = value;
                } else if (self.variables[v] != value) {
                    // there was a collision
                    return false;
                }
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

    fn getLastSet(self: Self) ?usize {
        return if (self.setting_order.items.len == 0)
            null
        else
            self.setting_order.items[self.setting_order.items.len - 1];
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
    literals: std.ArrayList(i32),
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
            try writer.print("{d}", .{literal});

            if (i != self.literals.items.len - 1) {
                try writer.print(" | ", .{});
            }
        }
    }

    pub fn isUnitClause(self: Self, variables: []Variable, variable: *i32) bool {
        return self.setVariables(variables, variable) == 1;
    }

    pub fn isEmptyClause(self: Self, variables: []Variable) bool {
        var bin: i32 = 0;
        return self.setVariables(variables, &bin) == 0;
    }

    fn setVariables(self: Self, variables: []Variable, last_set: *i32) usize {
        var set_items: usize = 0;

        for (self.literals.items) |item| {
            if (variables[@abs(item) - 1] == Variable.UNASSIGNED) {
                set_items += 1;
                last_set.* = item;
            }

            if (variables[@abs(item) - 1].isTrue()) {
                return 0;
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
        return self == .TEST_TRUE or self == .FORCE_TRUE;
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
