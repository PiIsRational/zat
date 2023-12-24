const std = @import("std");
const Allocator = std.mem.Allocator;
const Literal = @import("literal.zig").Literal;
const Clause = @import("clause.zig").Clause;
const ClauseHeader = @import("clause.zig").ClauseHeader;
const MemCell = @import("mem cell.zig").MemoryCell;
const Garbage = @import("mem garbage.zig").Garbage;
const ClauseDb = @import("clause db.zig").ClauseDb;

/// the struct used to allocate clauses
const ClauseAllocator = struct {
    database: *ClauseDb,
    literals: std.ArrayList(MemCell),

    /// the list containing the freed clauses
    free_list: []?*MemCell,

    /// the fragmentation counts the amount of literals contained in the free list
    /// if the fragmentation gets too large the free list should get defragmented
    fragmentation: usize,

    const Self = @This();

    pub fn init(allocator: Allocator, db: *ClauseDb, var_count: usize) !Self {
        var free_list = try allocator.alloc(?*MemCell, var_count + 1);

        return Self{
            .database = db,
            .literals = std.ArrayList(Literal).init(allocator),
            .fragmentation = 0,
            .free_list = free_list,
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

        garbage.next = self.free_list[len];
        self.free_list[len] = garbage;
    }

    // would be nice to have a way of defragmenting the heap
    pub fn defragment(self: Self) void {
        self.database.clauses.clearRetainingCapacity();
        var old_literals = self.literals;
        self.literals = std.ArrayList(MemCell).init(self.literals.allocator);

        var i: usize = 0;
        while (i < old_literals.items.len) : (i += 1) {
            var current = &old_literals.items[i];

            if (current.header.is_garbage) {
                i += current.garbage.len;
            } else {
                const old_clause = Clause.fromHeader(current);
                self.database.clauses.append(self.allocEnd(old_clause.getLength()));
            }
        }

        for (self.free_list) |*value| {
            value = null;
        }
    }

    pub fn deinit(self: *Self) void {
        self.literals.deinit();
        self.literals.allocator.free(self.free_list);
    }

    fn allocStandard(self: Self, size: usize) Clause {
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

        var header = &self.literals.items.ptr[self.literals.items.len - 1];

        self.literals.appendNTimes(MemCell{
            .literal = Literal{
                .is_garbage = false,
                .is_negated = false,
                .variable = 0,
            },
        }, size);

        return Clause.fromHeader(header.header);
    }
};
