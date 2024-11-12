const std = @import("std");

pub const Variable = enum(u8) {
    un_neg = 0,
    un_pos,
    neg,
    pos,

    pub fn getInverse(self: Variable) Variable {
        return @enumFromInt(@intFromEnum(self) ^ 1);
    }

    pub fn toggleAssign(self: Variable) Variable {
        return @enumFromInt(@intFromEnum(self) ^ 2);
    }

    pub fn toString(self: Variable) []const u8 {
        return switch (self) {
            .pos => "POS",
            .neg => "NEG",
            else => "UNASSIGNED",
        };
    }

    pub fn unassigned(self: Variable) bool {
        return (2 & @intFromEnum(self)) == 0;
    }

    pub fn format(
        self: Variable,
        comptime _: []const u8,
        _: std.fmt.FormatOptions,
        writer: anytype,
    ) !void {
        if (self == .neg) try writer.print("-", .{});
        if (self.unassigned()) try writer.print("~", .{});
    }
};
