const std = @import("std");
const assert = std.debug.assert;
const Impls = @import("impl.zig").Impls;

pub const Literal = packed struct {
    is_garbage: bool,
    is_negated: bool,
    variable: u30,

    comptime {
        assert(@sizeOf(Literal) == 4);
    }

    const Self = @This();

    pub fn init(is_negated: bool, variable: u30) Literal {
        return .{
            .is_negated = is_negated,
            .is_garbage = false,
            .variable = variable,
        };
    }

    pub fn fromIndex(index: usize) Literal {
        return .{
            .is_garbage = false,
            .is_negated = index & 1 == 1,
            .variable = @intCast(index >> 1),
        };
    }

    pub fn default() Literal {
        return .{
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
        return @as(u32, @bitCast(self)) == @as(u32, @bitCast(other));
    }

    pub fn toVar(self: Literal) usize {
        return self.variable;
    }

    /// returns the negated version of this literal
    pub fn negated(self: Self) Self {
        return .{
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
        comptime _: []const u8,
        _: std.fmt.FormatOptions,
        writer: anytype,
    ) !void {
        const sign = if (self.is_negated) "-" else "";

        try writer.print("{s}{}", .{ sign, self.variable + 1 });
    }
};
