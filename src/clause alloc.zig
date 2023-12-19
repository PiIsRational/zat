const std = @import("std");
const Allocator = std.mem.Allocator;
const Literal = @import("literal.zig").Literal;
const Clause = @import("clause.zig").Clause;
const ClauseHeader = @import("clause.zig").ClauseHeader;
const MemCell = @import("mem cell.zig").MemoryCell;
const Garbage = @import("mem garbage.zig").Garbage;

const STANDARD_CLAUSE_SIZES: usize = 10;

/// the struct used to allocate clauses
const ClauseAllocator = struct {
    literals: std.ArrayList(Literal),

    /// the list containing the freed clauses
    free_list: [STANDARD_CLAUSE_SIZES + 1]?*MemCell,

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
        return self.allocEnd(size);
        // if (size > STANDARD_CLAUSE_SIZES)
        //    self.allocLarge(size)
        //else
        //    self.allocStandard(size);
    }

    /// the method used to free a clause
    pub fn free(self: Self, clause: Clause) void {
        const len = clause.getLength();

        // add one because the clause length does not include the header
        self.fragmentation += len + 1;

        const garbage: *Garbage = Garbage.fromCells(clause.literals);
        garbage.*.header.is_garbage = true;
        garbage.*.header.len = len;

        if (len < STANDARD_CLAUSE_SIZES) {
            garbage.next = self.free_list[len];
            self.free_list[len] = garbage;
        } else {
            garbage.next = self.free_list[STANDARD_CLAUSE_SIZES];
            self.free_list[STANDARD_CLAUSE_SIZES] = garbage;
        }
    }

    // would be nice to have a way of defragmenting the heap
    // pub fn defragment(self: Self, ...)

    fn allocStandard(self: Self, size: usize) Clause {
        //TODO: implement
        _ = size;
        _ = self;
    }

    fn allocLarge(self: Self, size: usize) Clause {
        //TODO: implement
        _ = size;
        _ = self;
    }

    /// the default allocation strategy
    /// it does not ook at the free list at all
    fn allocEnd(self: Self, size: usize) Clause {
        self.literals.append(MemCell{
            .header = ClauseHeader{
                .is_garbage = false,
                .len = size,
            },
        });

        self.literals.appendNTimes(MemCell{
            .literal = Literal{
                .is_garbage = false,
                .is_negated = false,
                .variable = 0,
            },
        }, size);
    }
};
