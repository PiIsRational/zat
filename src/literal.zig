const std = @import("std");

pub const Literal = packed struct {
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
