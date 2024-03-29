const std = @import("std");
const Variable = @import("variable.zig").Variable;
const Impls = @import("impl.zig").Impls;

const PossibleResults = enum {
    UNSAT,
    SAT,
};

pub const SatResult = union(PossibleResults) {
    UNSAT,
    SAT: Impls,

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
                for (solution.impls, 1..) |var_state, var_num| {
                    if (var_num != 1) {
                        try writer.print(" ", .{});
                    }

                    try writer.print("{s}{}", .{ var_state.variable, var_num });
                }
            },
            .UNSAT => {},
        }
    }
};

pub const ResultTag = enum {
    FAIL,
    OK,
};

pub fn Result(comptime T: type) type {
    return union(ResultTag) {
        FAIL,
        OK: T,
    };
}
