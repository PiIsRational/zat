const std = @import("std");
const GarbageFlag = @import("mem cell.zig").GarbageFlag;
const LiteralFlag = @import("mem cell.zig").LiteralFlag;
const Literal = @import("literal.zig").Literal;
const Variable = @import("variable.zig").Variable;
const MemoryCell = @import("mem cell.zig").MemoryCell;

/// the clause struct
///
/// it points to its section of the clause memory
/// the first part of a clause is the clause header
/// it contains the meta informations about the clause
///
/// after that the literals are stored in order
pub const Clause = struct {
    literals: [*]MemoryCell,
    const Self = @This();

    /// sets the literals of
    pub fn setLiterals(self: *Self, literals: []Literal) void {
        @memcpy(self.getLiterals(), literals);
    }

    /// initializes a clause from the pointer to its header
    pub fn fromHeader(header: *ClauseHeader) Clause {
        return Clause{
            .literals = @ptrCast(header),
        };
    }

    /// checks if this clause points to garbage in memory
    pub fn isGarbage(self: Self) bool {
        return self.literals[0].header.is_garbage;
    }

    /// getter for the amount of literals in this clause
    pub fn getLength(self: Self) usize {
        return self.literals[0].header.len;
    }

    /// getter for the literals contained in this clause as a slice
    pub fn getLiterals(self: Self) []Literal {
        return @ptrCast(self.literals[1 .. self.getLength() + 1]);
    }

    pub fn format(
        self: Self,
        comptime fmt: []const u8,
        options: std.fmt.FormatOptions,
        writer: anytype,
    ) !void {
        _ = options;
        _ = fmt;

        for (self.getLiterals(), 0..) |literal, i| {
            try writer.print("{s}", .{literal});

            if (i != self.getLength() - 1) {
                try writer.print(" | ", .{});
            }
        }
    }
};

/// the clause header contains the meta-data of the clause
pub const ClauseHeader = packed struct {
    is_garbage: bool,
    len: u31,

    const Self = @This();
};
