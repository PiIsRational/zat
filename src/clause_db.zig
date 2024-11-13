const std = @import("std");
const assert = std.debug.assert;
const Allocator = std.mem.Allocator;
const Literal = @import("literal.zig").Literal;
const Clause = @import("clause.zig").Clause;
const ClauseHeader = @import("clause.zig").ClauseHeader;
const MemCell = @import("mem_cell.zig").MemoryCell;

const MIN_CLAUSE_SIZE: usize = 4;

/// ClauseDb is the database for all clauses with at least 3 literals
const ClauseDb = @This();

clauses: std.ArrayList(Clause),
memory: std.ArrayList(MemCell),
allocator: Allocator,

/// the list containing the freed clauses
free_list: []u32,

/// the fragmentation counts the amount of literals contained in the free list
/// if the fragmentation gets too large the database should get defragmented
fragmentation: usize = 0,

/// the constructor if the clause database
pub fn init(allocator: Allocator, variables: usize) !ClauseDb {
    // we want to alloc the first block of memory such that a clause
    // with an index of zero can be used equivalently to a null pointer
    var memory = std.ArrayList(MemCell).init(allocator);
    try memory.append(.{ .garbage = .{ .is_garbage = true, .len = 0 } });
    const free_list = try allocator.alloc(u32, approxLog(variables));
    @memset(free_list, 0);

    return .{
        .clauses = std.ArrayList(Clause).init(allocator),
        .allocator = allocator,
        .memory = memory,
        .free_list = free_list,
    };
}

fn approxLog(val: usize) usize {
    return @sizeOf(usize) * 8 - @clz(val);
}

fn getBucket(clause_len: usize) usize {
    return approxLog(clause_len - MIN_CLAUSE_SIZE);
}

/// adds a clause containing `literals` to the clause database
pub fn addClause(self: *ClauseDb, literals: []Literal) !Clause {
    var clause = try self.alloc(literals.len);
    @memcpy(clause.getLitsMut(self.*), literals);

    return clause;
}

/// the method used to allocate a clause
pub fn alloc(self: *ClauseDb, size: usize) !Clause {
    std.debug.assert(size >= 3);

    if (self.fragmentation > 0) {
        if (self.allocStandard(size)) |clause| return clause;
    }

    const clause = try self.allocEnd(@intCast(size));
    try self.clauses.append(clause);

    return clause;
}

/// frees `clause` from the clause database
pub fn free(self: ClauseDb, clause: *Clause) void {
    const len = clause.getLength(self);

    // add one because the clause length does not include the header
    self.fragmentation += len + 1;
    const mem_slice = self.memory.items;

    const garbage_slice = mem_slice[clause.index .. clause.index + len + 1];
    const bucket = getBucket(len);

    garbage_slice[0].garbage = .{
        .is_garbage = true,
        .len = len,
    };
    garbage_slice[1].next = self.free_list[bucket];

    self.free_list[bucket] = clause.index;
    clause.* = self.clauses.pop();
}

/// the destructor of the clause database
pub fn deinit(self: *ClauseDb) void {
    self.clauses.deinit();
    self.memory.deinit();
    self.allocator.free(self.free_list);
}

/// the function used to defragment the heap
fn defragment(self: *ClauseDb) void {
    // TODO: this is nice but needs to work with the watchlist
    self.clauses.clearRetainingCapacity();
    var old_literals = self.literals;
    self.literals = std.ArrayList(MemCell).init(self.literals.allocator);

    var i: usize = 0;
    while (i < old_literals.items.len) : (i += 1) {
        const current = &old_literals.items[i];

        if (current.header.is_garbage) {
            i += current.garbage.len;
        } else {
            const old_clause = Clause.fromHeader(current);
            try self.clauses.append(self.allocEnd(old_clause.getLength()));
            i += current.header.len;
        }
    }

    for (self.free_list) |*value| value = null;
}

fn allocStandard(self: *ClauseDb, size: usize) ?Clause {
    const bucket = getBucket(size);

    const bucket_list = self.free_list[bucket];
    const mem_slice = self.memory.items;

    if (bucket_list != 0) {
        const header = mem_slice[bucket_list];
        assert(header.garbage.is_garbage);
        const usable = header.garbage.len >= size;
        if (usable) return self.allocToGarbage(header, size, bucket_list);
    }

    if (bucket == self.free_list.len) return null;

    for (self.free_list[bucket + 1 ..]) |new_bucket| {
        if (new_bucket == 0) continue;

        // becuase we are in the next bucket list there is always enough space
        const header = mem_slice[new_bucket];
        assert(header.garbage.is_garbage);
        return self.allocToGarbage(header, size, bucket_list);
    }

    return null;
}

fn allocToGarbage(self: *ClauseDb, header: MemCell, size: usize, place: usize) Clause {
    const mem_slice = self.memory.items;
    const clause_slice = mem_slice[place .. place + size];
    clause_slice[0] = .{ .header = .{
        .is_garbage = false,
        .len = @intCast(size),
    } };

    // now that we allocated we can reduce the fragmentation count
    self.fragmentation -= size + 1;
    const new_clause = Clause.fromHeader(place);

    if (header.garbage.len <= size + MIN_CLAUSE_SIZE) return new_clause;

    const garbage_idx = place + size;
    const garbage_len = header.garbage.len - size - 1;

    mem_slice[garbage_idx] = .{ .garbage = .{
        .is_garbage = true,
        .len = @intCast(garbage_len),
    } };

    const bucket = getBucket(garbage_len);
    mem_slice[garbage_idx + 1].next = self.free_list[bucket];
    self.free_list[bucket] = @intCast(garbage_idx);

    return new_clause;
}

/// the default allocation strategy
/// it does not look at the free list at all
fn allocEnd(self: *ClauseDb, size: u32) !Clause {
    assert(size <= std.math.maxInt(u31));

    const header = self.memory.items.len;

    const clause_slice = try self.memory.addManyAsSlice(size + 1);
    clause_slice[0] = .{ .header = .{ .is_garbage = false, .len = @intCast(size) } };

    return Clause.fromHeader(header);
}

/// the amount of clauses contained in the model
pub fn getLength(self: ClauseDb) usize {
    return self.clauses.items.len;
}
