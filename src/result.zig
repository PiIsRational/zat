const std = @import("std");
const Variable = @import("variable.zig").Variable;
const Impls = @import("impl.zig").Impls;

const PossibleResults = enum { unsat, sat };

pub const SatResult = union(PossibleResults) {
    unsat,
    sat: Impls,

    pub fn toString(self: SatResult) [:0]const u8 {
        return switch (self) {
            .sat => "SATISFIABLE",
            .unsat => "UNSATISFIABLE",
        };
    }

    pub fn format(
        self: SatResult,
        comptime _: []const u8,
        _: std.fmt.FormatOptions,
        writer: anytype,
    ) !void {
        switch (self) {
            .sat => |solution| {
                for (solution.impls, 1..) |var_state, var_num| {
                    if (var_num != 1) try writer.print(" ", .{});
                    try writer.print("{s}{}", .{ var_state.variable, var_num });
                }
            },
            .unsat => {},
        }
    }
};
