const std = @import("std");
const assert = std.debug.assert;
const Literal = @import("literal.zig").Literal;
const ClauseHeader = @import("clause.zig").ClauseHeader;

pub const ClauseTier = enum(u8) {
    core,
    mid,
    local,

    pub fn fromLbd(lbd: u16) ClauseTier {
        if (lbd <= 2) return .core;
        if (lbd <= 6) return .mid;
        return .local;
    }
};

pub const MemoryCell = packed union {
    literal: Literal,
    header: ClauseHeader,
    garbage: GarbageHeader,

    // used to point to the next garbage in the free list
    next: u32,

    // the heuristic score of the clause
    score: f32,

    // the usefullness tracker of the clause
    use: packed struct {
        tier: ClauseTier,
        used: bool = false,
        conflict: bool = false,
        lbd: u16,
    },
};

pub const GarbageHeader = packed struct {
    is_garbage: bool,
    len: u31,

    comptime {
        assert(@sizeOf(ClauseHeader) == 4);
    }
};

test "attr invariance" {
    const cell: MemoryCell = .{ .literal = .{
        .is_garbage = true,
        .is_negated = false,
        .variable = 111111111,
    } };

    assert(@sizeOf(MemoryCell) == 4);
    assert(cell.garbage.is_garbage);
    assert(cell.header.is_garbage);
    assert(cell.header.len == cell.garbage.len);
}
