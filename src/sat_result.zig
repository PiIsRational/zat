const std = @import("std");
const Variable = @import("variable.zig").Variable;

const PossibleResults = enum {
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
