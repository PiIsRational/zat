const std = @import("std");
const GarbageFlag = @import("mem cell.zig").GarbageFlag;
const LiteralFlag = @import("mem cell.zig").LiteralFlag;
const Literal = @import("literal.zig").Literal;
const Variable = @import("variable.zig").Variable;
const MemoryCell = @import("mem cell.zig").MemoryCell;
const SatInstance = @import("sat instance.zig").SatInstance;

/// the clause struct
///
/// it points to its section of the clause memory
/// the first part of a clause is the clause header
/// it contains the meta informations about the clause
///
/// after that the literals are stored in order
pub const Clause = struct {
    cells: [*]MemoryCell,
    const Self = @This();

    /// sets the literals of
    pub fn setLiterals(self: *Self, literals: []Literal) void {
        @memcpy(self.getLiterals(), literals);
    }

    /// initializes a clause from the pointer to its header
    pub fn fromHeader(header: *ClauseHeader) Clause {
        return Clause{
            .cells = @ptrCast(header),
        };
    }

    /// checks if this clause points to garbage in memory
    pub fn isGarbage(self: Self) bool {
        return self.cells[0].header.is_garbage;
    }

    /// getter for the amount of literals in this clause
    pub fn getLength(self: Self) usize {
        return self.cells[0].header.len;
    }

    /// getter for the literals contained in this clause as a slice
    pub fn getLiterals(self: Self) []Literal {
        return @ptrCast(self.cells[1 .. self.getLength() + 1]);
    }

    /// checks that this clause is satisfied
    pub fn isSatisfied(self: Self, instance: *SatInstance) bool {
        for (self.getLiterals()) |lit| {
            if (instance.isTrue(lit)) {
                return true;
            }
        }

        return false;
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
