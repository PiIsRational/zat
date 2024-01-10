const std = @import("std");
const assert = std.debug.assert;
const Impls = @import("impl.zig").Impls;

pub const Literal = packed struct {
    is_garbage: bool,
    is_negated: bool,
    variable: u30,

    const Self = @This();

    pub fn init(is_negated: bool, variable: u30) Literal {
        return Literal{
            .is_negated = is_negated,
            .is_garbage = false,
            .variable = variable,
        };
    }

    pub fn fromIndex(index: usize) Literal {
        return Literal{
            .is_garbage = false,
            .is_negated = index & 1 == 1,
            .variable = @intCast(index >> 1),
        };
    }

    pub fn default() Literal {
        return Literal{
            .is_garbage = false,
            .is_negated = false,
            .variable = 0,
        };
    }

    /// converts a literal to an index for slices or arrays
    pub fn toIndex(self: Self) usize {
        return @as(usize, @intCast(self.variable << 1)) + if (self.is_negated)
            @as(usize, 1)
        else
            @as(usize, 0);
    }

    pub fn eql(self: Self, other: Self) bool {
        assert(!self.is_garbage and !other.is_garbage);

        return self.variable == other.variable and self.is_negated == other.is_negated;
    }

    /// returns the negated version of this literal
    pub fn negated(self: Self) Self {
        return Literal{
            .is_garbage = false,
            .is_negated = !self.is_negated,
            .variable = self.variable,
        };
    }

    /// this is a debugging method to check the sanity of literals
    pub fn isGood(self: Self, impls: Impls) bool {
        return !self.is_garbage and self.variable < impls.impls.len;
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
