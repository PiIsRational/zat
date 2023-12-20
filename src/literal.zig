const std = @import("std");

pub const Literal = packed struct {
    is_garbage: bool,
    is_negated: bool,
    variable: u30,

    const Self = @This();

    /// converts a literal to an index for slices or arrays
    pub fn toIndex(self: Self) usize {
        return self.variable << 2 + (if (self.is_negated) 1 else 0);
    }

    /// returns the negated version of this literal
    pub fn negated(self: Self) Self {
        return Literal{
            .is_garbage = false,
            .is_negated = !self.is_negated,
            .variable = self.variable,
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

        const sign = if (self.is_negated) "-" else "";

        try writer.print("{s}{}", .{ sign, self.variable + 1 });
    }
};
