const std = @import("std");
const assert = std.debug.assert;
const Literal = @import("literal.zig").Literal;
const ClauseHeader = @import("clause.zig").ClauseHeader;

pub const MemoryCell = packed union {
    literal: Literal,
    header: ClauseHeader,
    garbage: GarbageHeader,

    // used to point to the next garbage in the free list
    next: u32,
};

pub const GarbageHeader = packed struct {
    is_garbage: bool,
    len: u31,

    comptime {
        assert(@sizeOf(ClauseHeader) == 4);
    }
};

test "attr invariance" {
    const cell: MemoryCell = .{
        .literal = .{
            .is_garbage = true,
            .is_negated = false,
            .variable = 111111111,
        },
    };

    assert(@sizeOf(MemoryCell) == 4);
    assert(cell.garbage.is_garbage);
    assert(cell.header.is_garbage);
    assert(cell.header.len == cell.garbage.len);
}
