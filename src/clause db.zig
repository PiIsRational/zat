const std = @import("std");
const Allocator = std.mem.Allocator;
const Literal = @import("literal.zig").Literal;
const Clause = @import("clause.zig").Clause;
const ClauseHeader = @import("clause.zig").ClauseHeader;
const MemCell = @import("mem cell.zig").MemoryCell;
const Garbage = @import("mem garbage.zig").Garbage;

/// ClauseDb is the database for all clauses with at least 3 literals
pub const ClauseDb = struct {
    clauses: std.ArrayList(Clause),
    memory: std.ArrayList(MemCell),
    allocator: Allocator,

    /// the list containing the freed clauses
    free_list: []?*MemCell,

    /// the fragmentation counts the amount of literals contained in the free list
    /// if the fragmentation gets too large the free list should get defragmented
    fragmentation: usize,

    const Self = @This();

    /// the constructor if the clause database
    pub fn init(allocator: Allocator, variables: usize) !Self {
        return ClauseDb{
            .clauses = std.ArrayList(Clause).init(allocator),
            .allocator = allocator,
            .memory = std.ArrayList(MemCell).init(allocator),
            .fragmentation = 0,
            .free_list = try allocator.alloc(?*MemCell, variables + 1),
        };
    }

    /// adds a clause containing `literals` to the clause database
    pub fn addClause(self: *Self, literals: []Literal) !Clause {
        var clause = try self.alloc(literals.len);
        @memcpy(clause.getLiterals(), literals);

        return clause;
    }

    /// the method used to allocate a clause
    pub fn alloc(self: *Self, size: usize) !Clause {
        std.debug.assert(size >= 3);

        var clause = try self.allocEnd(@intCast(size));
        try self.clauses.append(clause);

        return clause;
    }

    /// frees `clause` from the clause database
    pub fn free(self: Self, clause: *Clause) void {
        const len = clause.getLength();

        // add one because the clause length does not include the header
        self.fragmentation += len + 1;

        const garbage: *Garbage = Garbage.fromCells(clause.*.cells);
        garbage.*.header.is_garbage = true;
        garbage.*.header.len = len;

        garbage.next = self.free_list[len];
        self.free_list[len] = garbage;

        clause.* = self.clauses.pop();
    }

    /// the destructor of the clause database
    pub fn deinit(self: *Self) void {
        self.clauses.deinit();
        self.memory.deinit();
        self.allocator.free(self.free_list);
    }

    /// the function used to defragment the heap
    fn defragment(self: *Self) void {
        self.clauses.clearRetainingCapacity();
        var old_literals = self.literals;
        self.literals = std.ArrayList(MemCell).init(self.literals.allocator);

        var i: usize = 0;
        while (i < old_literals.items.len) : (i += 1) {
            var current = &old_literals.items[i];

            if (current.header.is_garbage) {
                i += current.garbage.len;
            } else {
                const old_clause = Clause.fromHeader(current);
                try self.clauses.append(self.allocEnd(old_clause.getLength()));
                i += current.header.len;
            }
        }

        for (self.free_list) |*value| {
            value = null;
        }
    }

    fn allocStandard(self: Self, size: usize) Clause {
        //TODO: implement
        _ = size;
        _ = self;
    }

    /// the default allocation strategy
    /// it does not look at the free list at all
    fn allocEnd(self: *Self, size: u31) !Clause {
        if (self.memory.capacity <= self.memory.items.len + size + 1) {
            try self.memory.ensureTotalCapacity(self.memory.items.len + size + 1);
            self.clausesFromMem();
        }

        self.memory.appendAssumeCapacity(MemCell{
            .header = ClauseHeader{
                .is_garbage = false,
                .len = size,
            },
        });

        var header = &self.memory.items[self.memory.items.len - 1].header;
        self.memory.appendNTimesAssumeCapacity(MemCell{
            .literal = Literal.default(),
        }, size);

        return Clause.fromHeader(header);
    }

    /// set the clauses
    fn clausesFromMem(self: *Self) void {
        self.clauses.clearRetainingCapacity();

        var i: usize = 0;
        while (i < self.memory.items.len) : (i += 1) {
            var current = &self.memory.items[i];

            if (current.header.is_garbage) {
                i += current.garbage.len;
            } else {
                self.clauses.appendAssumeCapacity(
                    Clause.fromHeader(&current.header),
                );
                i += current.header.len;
            }
        }
    }

    /// the amount of clauses contained in the model
    pub fn getLength(self: Self) usize {
        return self.clauses.items.len;
    }
};
