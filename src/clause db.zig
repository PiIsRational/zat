const std = @import("std");
const Allocator = std.mem.Allocator;
const Clause = @import("clause.zig").Clause;
const ClauseAlloc = @import("clause alloc.zig").ClauseAllocator;
const Literal = @import("literal.zig").Literal;

/// ClauseDb is the database for all clauses with at least 3 literals
pub const ClauseDb = struct {
    clauses: std.ArrayList(Clause),
    clause_alloc: ClauseAlloc,
    allocator: Allocator,

    const Self = @This();

    /// the constructor if the clause database
    pub fn init(allocator: Allocator) Self {
        return ClauseDb{
            .clause = std.ArrayList(Clause).init(allocator),
            .clause_alloc = ClauseAlloc.init(Allocator),
            .allocator = allocator,
        };
    }

    /// adds a clause containing `literals` to the clause database
    pub fn addClause(self: *Self, literals: []Literal) !void {
        var clause = try self.clause_alloc.alloc(literals.len);
        @memcpy(clause.getLiterals(), literals);
        try self.clauses.append(clause);
    }

    /// the amount of clauses contained in the model
    pub fn getLength(self: *Self) usize {
        return self.clauses.items.len;
    }

    /// removes `clause` from the clause database
    pub fn removeClause(self: *Self, clause: *Clause) void {
        self.clause_alloc.free(clause.*);
        clause.* = self.clauses.pop();
    }

    /// the destructor of the clause database
    pub fn deinit(self: *Self) void {
        self.clause_alloc.deinit();
        self.clauses.deinit();
    }
};
