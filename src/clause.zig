const std = @import("std");
const Allocator = std.mem.Allocator;
const assert = std.debug.assert;
const Literal = @import("literal.zig").Literal;
const Variable = @import("variable.zig").Variable;
const MemoryCell = @import("mem_cell.zig").MemoryCell;
const ClauseTier = @import("mem_cell.zig").ClauseTier;
const SatInstance = @import("sat_instance.zig").SatInstance;
const ClauseDb = @import("clause_db.zig");
const WatchList = @import("watch.zig").WatchList;

const MIN_CLAUSE_SIZE = CLAUSE_HEADER_SIZE + MIN_CLAUSE;
const CLAUSE_HEADER_SIZE: usize = 2;
const MIN_CLAUSE: usize = 3;

/// the Clause struct.
///
/// it contains the index to the header of the corresponding clause in the clause memory
pub const Clause = struct {
    index: u32,
    const Self = @This();

    /// sets the literals of
    pub fn setLiterals(self: *Self, db: *const ClauseDb, literals: []Literal) void {
        @memcpy(self.getLiterals(db), literals);
    }

    /// initializes a clause from the index to its header
    pub fn fromHeader(header_idx: usize) Clause {
        return .{ .index = @intCast(header_idx) };
    }

    /// returns a null clause (it points to nothing)
    pub fn getNull() Clause {
        return .{ .index = 0 };
    }

    pub fn getTier(self: Self, db: ClauseDb) ClauseTier {
        return db.memory.items[self.index + 1].use.tier;
    }

    pub fn setTier(self: Self, db: ClauseDb, tier: ClauseTier) void {
        db.memory.items[self.index + 1].use.tier = tier;
    }

    pub fn getLbd(self: Self, db: ClauseDb) u16 {
        return db.memory.items[self.index + 1].use.lbd;
    }

    pub fn setLbd(self: Self, db: ClauseDb, lbd: u16) void {
        db.memory.items[self.index + 1].use.lbd = lbd;
    }

    pub fn setUsed(self: Self, db: ClauseDb, flag: bool) void {
        db.memory.items[self.index + 1].use.used = flag;
    }

    pub fn getUsed(self: Self, db: ClauseDb) bool {
        return db.memory.items[self.index + 1].use.used;
    }

    pub fn setConflict(self: Self, db: ClauseDb, flag: bool) void {
        db.memory.items[self.index + 1].use.conflict = flag;
    }

    pub fn getConflict(self: Self, db: ClauseDb) bool {
        return db.memory.items[self.index + 1].use.conflict;
    }

    /// checks if this clause points to garbage in memory
    pub fn isGarbage(self: Self, db: ClauseDb) bool {
        return db.memory.items[self.index].header.is_garbage;
    }

    /// checks if this clause points to nothing
    pub fn isNull(self: Self) bool {
        return self.index == 0;
    }

    /// getter for the amount of literals in this clause
    pub fn getLength(self: Self, db: ClauseDb) usize {
        return db.memory.items[self.index].header.len;
    }

    /// getter for the literals contained in this clause as a const slice
    pub fn getLiterals(self: Self, db: ClauseDb) []const Literal {
        return self.getLitsMut(db);
    }

    /// getter for the literals as a normal slice
    pub fn getLitsMut(self: Self, db: ClauseDb) []Literal {
        return @ptrCast(db.memory.items[self.index +
            CLAUSE_HEADER_SIZE .. self.index + self.getLength(db) + CLAUSE_HEADER_SIZE]);
    }

    /// checks that this clause is satisfied
    pub fn isSatisfied(self: Self, instance: SatInstance) bool {
        for (self.getLiterals(instance.clauses)) |lit| {
            if (instance.isTrue(lit)) return true;
        }

        return false;
    }

    pub fn fullyAssigned(self: Self, instance: SatInstance) bool {
        for (self.getLiterals(&instance.clauses)) |lit| {
            if (instance.unassigned(lit)) return false;
        }

        return true;
    }

    pub fn isUnit(self: Self, instance: SatInstance) bool {
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
    pub fn getRef(self: Self, db: ClauseDb) ClauseRef {
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
///
/// this structure should be kept shortlived as it can be invalidated
/// after allocating a new clause on the `ClauseDb`
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
};

pub const ClauseHeuristic = struct {
    var stats: struct {
        mid_count: usize = 0,
        mid_tier_update: usize = 0,
        local_count: usize = 0,
        freed_locals: usize = 0,
    } = .{};

    tier_lookup: []bool,

    pub fn init(allocator: Allocator, variables: usize) !ClauseHeuristic {
        return .{ .tier_lookup = try allocator.alloc(bool, variables) };
    }

    pub fn computeGlue(
        self: *ClauseHeuristic,
        instance: SatInstance,
        lits: []const Literal,
    ) u16 {
        var lbd: u16 = 0;
        for (lits) |lit| {
            const level = instance.variables.getChoiceCount(lit.toVar());
            if (self.tier_lookup[level]) continue;
            self.tier_lookup[level] = true;
            lbd += 1;
        }

        for (lits) |lit| {
            const level = instance.variables.getChoiceCount(lit.toVar());
            self.tier_lookup[level] = false;
        }

        return lbd;
    }

    pub fn deinit(self: ClauseHeuristic, allocator: Allocator) void {
        allocator.free(self.tier_lookup);
    }

    pub fn moveMid(_: ClauseHeuristic, db: ClauseDb, watch: *WatchList) void {
        for (watch.watches) |watches| {
            for (watches.items) |w| {
                const clause = w.clause;
                if (clause.getTier(db) != .mid) continue;
                if (clause.getConflict(db)) continue;

                ClauseHeuristic.stats.mid_count += 1;
                ClauseHeuristic.stats.mid_tier_update += 1;
                clause.setTier(db, .local);
            }
        }

        for (watch.watches) |watches| {
            for (watches.items) |w| {
                const clause = w.clause;
                if (clause.getTier(db) != .mid) continue;
                if (!clause.getConflict(db)) continue;

                ClauseHeuristic.stats.mid_count += 1;
                clause.setConflict(db, false);
            }
        }
    }

    pub fn freeLocal(_: ClauseHeuristic, db: ClauseDb, watch: *WatchList) !void {
        for (watch.watches) |watches| {
            for (watches.items) |w| {
                const clause = w.clause;
                if (clause.isGarbage(db) or clause.getTier(db) != .local) continue;

                // the idea is that clauses that have seen some use
                ClauseHeuristic.stats.local_count += 1;
                if (clause.getConflict(db)) {
                    clause.setTier(db, .mid);
                    clause.setConflict(db, false);
                } else if (!clause.getUsed(db)) {
                    ClauseHeuristic.stats.freed_locals += 1;
                    try db.free(clause, watch);
                } else {
                    ClauseHeuristic.stats.local_count -= 1;
                }
            }
        }
    }
};
