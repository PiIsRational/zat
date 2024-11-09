const std = @import("std");
const assert = std.debug.assert;
const GarbageFlag = @import("mem_cell.zig").GarbageFlag;
const LiteralFlag = @import("mem_cell.zig").LiteralFlag;
const Literal = @import("literal.zig").Literal;
const Variable = @import("variable.zig").Variable;
const MemoryCell = @import("mem_cell.zig").MemoryCell;
const SatInstance = @import("sat_instance.zig").SatInstance;
const ClauseDb = @import("clause_db.zig").ClauseDb;

/// the Clause struct.
///
/// it contains the index to the header of the corresponding clause in the clause memory
pub const Clause = struct {
    index: usize,
    const Self = @This();

    /// sets the literals of
    pub fn setLiterals(self: *Self, db: *const ClauseDb, literals: []Literal) void {
        @memcpy(self.getLiterals(db), literals);
    }

    /// initializes a clause from the index to its header
    pub fn fromHeader(header_idx: usize) Clause {
        return .{ .index = header_idx };
    }

    /// returns a null clause (it points to nothing)
    pub fn getNull() Clause {
        return .{ .index = 0 };
    }

    /// checks if this clause points to garbage in memory
    pub fn isGarbage(self: Self, db: *const ClauseDb) bool {
        return db.*.memory.items[self.index].header.is_garbage;
    }

    /// checks if this clause points to nothing
    pub fn isNull(self: Self) bool {
        return self.index == 0;
    }

    /// getter for the amount of literals in this clause
    pub fn getLength(self: Self, db: *const ClauseDb) usize {
        return db.memory.items[self.index].header.len;
    }

    /// getter for the literals contained in this clause as a const slice
    pub fn getLiterals(self: Self, db: *const ClauseDb) []const Literal {
        return self.getLitsMut(db);
    }

    /// getter for the literals as a normal slice
    pub fn getLitsMut(self: Self, db: *const ClauseDb) []Literal {
        return @ptrCast(db.memory
            .items[self.index + 1 .. self.index + self.getLength(db) + 1]);
    }

    /// checks that this clause is satisfied
    pub fn isSatisfied(self: Self, instance: *const SatInstance) bool {
        for (self.getLiterals(&instance.*.clauses)) |lit| {
            if (instance.isTrue(lit)) return true;
        }

        return false;
    }

    pub fn fullyAssigned(self: Self, instance: *const SatInstance) bool {
        for (self.getLiterals(&instance.clauses)) |lit| {
            if (instance.unassigned(lit)) return false;
        }

        return true;
    }

    pub fn isUnit(self: Self, instance: *const SatInstance) bool {
        var found_unassigned = false;

        for (self.getLiterals(&instance.clauses)) |lit| {
            if (instance.unassigned(lit)) {
                if (found_unassigned) return false;
                found_unassigned = true;
            }

            if (instance.isTrue(lit)) return false;
        }

        return found_unassigned;
    }

    /// returns the reference to the memory behind this clause
    pub fn getRef(self: Self, db: *const ClauseDb) ClauseRef {
        return .{ .lits = self.getLiterals(db) };
    }
};

/// the clause ref struct
///
/// it points to its section of the clause memory
/// the first part of a clause is the clause header
/// it contains the meta informations about the clause
///
/// after that the literals are stored in order
pub const ClauseRef = struct {
    lits: []const Literal,

    const Self = @This();

    /// getter for the length of this clause
    pub fn getLength(self: Self) usize {
        return self.lits.len;
    }

    /// getter for the literals of this clause
    pub fn getLiterals(self: Self) []const Literal {
        return self.lits;
    }

    pub fn format(
        self: Self,
        comptime _: []const u8,
        _: std.fmt.FormatOptions,
        writer: anytype,
    ) !void {
        const lits = self.getLiterals();
        if (lits.len == 0) return;
        try writer.print("{s}", .{lits[0]});
        for (lits) |lit| try writer.print(" | {s}", .{lit});
    }
};

/// the clause header contains the meta-data of the clause
pub const ClauseHeader = packed struct {
    is_garbage: bool,
    len: u31,

    comptime {
        assert(@sizeOf(ClauseHeader) == 4);
    }

    const Self = @This();
};
