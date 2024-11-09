const std = @import("std");

pub const Variable = enum(i8) {
    unassigned = -1,
    test_false,
    test_true,
    force_false,
    force_true,

    const Self = @This();

    /// checks if the variable is forced or unassigned
    pub fn isForce(self: Self) bool {
        return @intFromEnum(self) >> 1 == 1;
    }

    /// true iff this variable is true or unassigned
    pub fn isTrue(self: Self) bool {
        return @intFromEnum(self) & 1 == 1;
    }

    /// checks if this variable is false
    pub fn isFalse(self: Self) bool {
        return @intFromEnum(self) & 1 == 0;
    }

    /// check if two variables have an equal value
    pub fn isEqual(self: Self, other: Self) bool {
        return (self == .unassigned) == (other == .unassigned) and
            self.isTrue() == other.isTrue();
    }

    pub fn getInverse(self: Self) Variable {
        return switch (self) {
            .test_false => .force_true,
            .test_true => .force_false,
            .force_false => .test_true,
            .force_true => .test_false,
            else => .unassigned,
        };
    }

    pub fn toString(self: Self) []const u8 {
        return switch (self) {
            .test_false => "TEST_TRUE",
            .test_false => "TEST_FALSE",
            .force_true => "FORCE_TRUE",
            .force_false => "FORCE_FALSE",
            else => "UNASSIGNED",
        };
    }

    pub fn format(
        self: Self,
        comptime _: []const u8,
        _: std.fmt.FormatOptions,
        writer: anytype,
    ) !void {
        if (self.isFalse()) try writer.print("-", .{});
        if (self == .unassigned) try writer.print("~", .{});
    }
};
