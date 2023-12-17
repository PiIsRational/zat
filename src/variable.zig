const std = @import("std");

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
        return self == .TEST_FALSE or self == .FORCE_TRUE;
    }

    pub fn isEqual(self: Self, other: Self) bool {
        const self_true = self.isTrue();
        const other_true = other.isForce();

        return self_true and other_true or !self_true and !other_true;
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
