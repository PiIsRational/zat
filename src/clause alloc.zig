const std = @import("std");
const Allocator = std.mem.Allocator;
const Literal = @import("literal.zig").Literal;
const Clause = @import("clause.zig").Clause;

const STANDARD_CLAUSE_SIZES: usize = 10;

const ClauseAllocator = struct {
    literals: std.ArrayList(Literal),

    /// the list containing the freed clauses
    free_list: [STANDARD_CLAUSE_SIZES + 1]std.SinglyLinkedList([]Literal),

    /// the fragmentation counts the amount of literals contained in the free list
    /// if the fragmentation gets too large the free list should get defragmented
    fragmentation: usize,

    const Self = @This();

    pub fn init(allocator: Allocator) Self {
        return Self{
            .literals = std.ArrayList(Literal).init(allocator),
        };
    }

    /// the method used to allocate a clause
    pub fn alloc(self: Self, size: usize) Clause {
        return if (size > STANDARD_CLAUSE_SIZES)
            self.allocLarge(size)
        else
            self.allocStandard(size);
    }

    /// the method used to free a clause
    pub fn free(self: Self, clause: Clause) void {
        if (clause.literals.len <= STANDARD_CLAUSE_SIZES) {
            self.free_list[clause.literals.len].prepend(std.Node{});
        }
    }

    // would be nice to have a way of defragmenting the heap
    // pub fn defragment(self: Self, )

    fn allocStandard(self: Self, size: usize) Clause {
        _ = size;
        _ = self;
    }

    fn allocLarge(self: Self, size: usize) Clause {
        for (self.free_list[STANDARD_CLAUSE_SIZES]) |slice| {
            if (slice.len >= size) {
                return Clause{
                    .literals = slice[0..size],
                };
            }
        }
    }
};
