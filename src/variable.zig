const std = @import("std");

pub const Variable = enum(u8) {
    unassigned,
    pos,
    neg,

    const Self = @This();

    pub fn getInverse(self: Self) Variable {
        return switch (self) {
            .pos => .neg,
            .neg => .pos,
            else => .unassigned,
        };
    }

    pub fn toString(self: Self) []const u8 {
        return switch (self) {
            .pos => "POS",
            .neg => "NEG",
            else => "UNASSIGNED",
        };
    }

    pub fn format(
        self: Self,
        comptime _: []const u8,
        _: std.fmt.FormatOptions,
        writer: anytype,
    ) !void {
        if (self == .neg) try writer.print("-", .{});
        if (self == .unassigned) try writer.print("~", .{});
    }
};
