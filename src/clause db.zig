const std = @import("std");
const Allocator = std.mem.Allocator;
const Clause = @import("clause.zig").Clause;
const ClauseAlloc = @import("clause alloc.zig").ClauseAllocator;

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
};
