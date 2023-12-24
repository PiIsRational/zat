const std = @import("std");
const Allocator = std.mem.Allocator;
const Clause = @import("clause.zig").Clause;
const ClauseAlloc = @import("clause alloc.zig").ClauseAllocator;
const Literal = @import("literal.zig").Literal;

/// ClauseDb is the database for all clauses with at least 3 literals
const ClauseDb = struct {
    clauses: std.ArrayList(Clause),
    clause_alloc: ClauseAlloc,
    allocator: Allocator,

    const Self = @This();

    pub fn init(allocator: Allocator) Self {
        return ClauseDb{
            .clause = std.ArrayList(Clause).init(allocator),
            .clause_alloc = ClauseAlloc.init(Allocator),
            .allocator = allocator,
        };
    }

    /// adds a clause containing `literals` to the clause database
    pub fn addClause(self: *Self, literals: []Literal) void {
        var clause = self.clause_alloc.alloc(literals.len);
        @memcpy(clause.getLiterals(), literals);
        self.clauses.append(clause);
    }

    /// removes `clause` from the clause database
    pub fn removeClause(self: *Self, clause: *Clause) void {
        self.clause_alloc.free(clause.*);
        clause.* = self.clauses.pop();
    }
};
