const std = @import("std");

pub const Variable = enum(i8) {
    UNASSIGNED = -1,
    TEST_FALSE,
    TEST_TRUE,
    FORCE_FALSE,
    FORCE_TRUE,

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
        return (self == .UNASSIGNED) == (other == .UNASSIGNED) and
            self.isTrue() == other.isTrue();
    }

    pub fn getInverse(self: Self) Variable {
        return switch (self) {
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

        if (self.isFalse()) {
            try writer.print("-", .{});
        }

        if (self == .UNASSIGNED) {
            try writer.print("~", .{});
        }
    }
};
