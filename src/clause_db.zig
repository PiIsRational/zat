const std = @import("std");
const assert = std.debug.assert;
const Allocator = std.mem.Allocator;
const Literal = @import("literal.zig").Literal;
const Clause = @import("clause.zig").Clause;
const ClauseHeader = @import("clause.zig").ClauseHeader;
const MemCell = @import("mem_cell.zig").MemoryCell;
const ClauseTier = @import("mem_cell.zig").ClauseTier;
const WatchList = @import("watch.zig").WatchList;

const MIN_CLAUSE_SIZE = CLAUSE_HEADER_SIZE + MIN_CLAUSE_LITS;
const CLAUSE_HEADER_SIZE: usize = 2;
const MIN_CLAUSE_LITS: usize = 3;

/// ClauseDb is the database for all clauses with at least 3 literals
const ClauseDb = @This();

memory: std.ArrayList(MemCell),
allocator: Allocator,

/// the list containing the freed clauses
free_list: []u32,

/// the fragmentation counts the amount of literals contained in the free list
/// if the fragmentation gets too large the database should get defragmented
fragmentation: usize = 0,
clause_count: usize = 0,
variables: usize,

/// the constructor if the clause database
pub fn init(allocator: Allocator, variables: usize) !ClauseDb {
    // we want to alloc the first block of memory such that a clause
    // with an index of zero can be used equivalently to a null pointer
    var memory = std.ArrayList(MemCell).init(allocator);
    try memory.append(.{ .garbage = .{ .is_garbage = true, .len = 0 } });
    const free_list = try allocator.alloc(u32, approxLog(variables));
    @memset(free_list, 0);

    return .{
        .allocator = allocator,
        .memory = memory,
        .free_list = free_list,
        .variables = variables,
    };
}

fn approxLog(val: usize) usize {
    return @sizeOf(usize) * 8 - @clz(val);
}

fn getBucket(clause_len: usize) usize {
    return approxLog(clause_len - MIN_CLAUSE_SIZE);
}

/// adds a clause containing `literals` to the clause database
pub fn addClause(self: *ClauseDb, literals: []Literal, lbd: u16, watch: *WatchList) !Clause {
    var clause = try self.alloc(literals.len);
    clause.setLbd(self.*, lbd);
    clause.setTier(self.*, ClauseTier.fromLbd(lbd));
    @memcpy(clause.getLitsMut(self.*), literals);

    try watch.append(clause, .{ literals[0], literals[1] }, self.*);
    return clause;
}

/// the method used to allocate a clause
pub fn alloc(self: *ClauseDb, size: usize) !Clause {
    std.debug.assert(size >= MIN_CLAUSE_LITS);
    self.clause_count += 1;

    if (self.fragmentation > 0) {
        if (self.allocStandard(size)) |clause| return clause;
    }

    const clause = try self.allocEnd(@intCast(size));

    return clause;
}

/// frees `clause` from the clause database
pub fn free(self: ClauseDb, clause: Clause, watch: *WatchList) !void {
    const len = clause.getLength(self);
    self.clause_count -= 1;

    self.fragmentation += len + CLAUSE_HEADER_SIZE;
    const mem_slice = self.memory.items;

    const garbage_slice = mem_slice[clause.index .. clause.index + len + CLAUSE_HEADER_SIZE];
    const bucket = getBucket(len);

    garbage_slice[0].garbage = .{ .is_garbage = true, .len = len };
    garbage_slice[1].next = self.free_list[bucket];

    self.free_list[bucket] = clause.index;

    if (self.fragmentation < self.memory.items.len / 2) try self.defragment(watch);
}

/// the destructor of the clause database
pub fn deinit(self: *ClauseDb) void {
    self.memory.deinit();
    self.allocator.free(self.free_list);
}

/// the function used to defragment the heap
fn defragment(self: *ClauseDb, watch: *WatchList) !void {
    const current_self = self.*;
    self.* = try init(current_self.allocator, current_self.variables);

    for (watch.watches) |watches| {
        for (watches.items) |*w| {
            if (w.clause.isGarbage(current_self)) continue;
            const literals = w.clause.getLitsMut(current_self);
            const lbd = w.clause.getLbd(current_self);
            var clause = try self.allocEnd(literals.len);
            clause.setLbd(self.*, lbd);
            clause.setTier(self.*, ClauseTier.fromLbd(lbd));
            @memcpy(clause.getLitsMut(self.*), literals);
            w.clause = clause;
        }
    }

    current_self.deinit();
}

fn allocStandard(self: *ClauseDb, size: usize) ?Clause {
    const bucket = getBucket(size);

    const bucket_list = self.free_list[bucket];
    const mem_slice = self.memory.items;

    if (bucket_list != 0) {
        const header = mem_slice[bucket_list];
        assert(header.garbage.is_garbage);
        const usable = header.garbage.len + 1 >= size + CLAUSE_HEADER_SIZE;
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
    self.fragmentation -= size + CLAUSE_HEADER_SIZE;
    const new_clause = Clause.fromHeader(place);

    if (header.garbage.len <= size + MIN_CLAUSE_SIZE) return new_clause;

    const garbage_idx = place + size;
    const garbage_len = header.garbage.len - size - CLAUSE_HEADER_SIZE;

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

    const clause_slice = try self.memory.addManyAsSlice(size + CLAUSE_HEADER_SIZE);
    clause_slice[0] = .{ .header = .{ .is_garbage = false, .len = @intCast(size) } };

    return Clause.fromHeader(header);
}

/// the amount of clauses contained in the model
pub fn getLength(self: ClauseDb) usize {
    return self.clause_count;
}
