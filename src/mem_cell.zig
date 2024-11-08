const std = @import("std");
const assert = std.debug.assert;
const Literal = @import("literal.zig").Literal;
const ClauseHeader = @import("clause.zig").ClauseHeader;
const Garbage = @import("mem_garbage.zig").GarbageHeader;

pub const MemoryCell = packed union {
    literal: Literal,
    header: ClauseHeader,
    garbage: Garbage,
    integer: u32,
};

test "attr invariance" {
    const cell: MemoryCell = .{
        .literal = .{
            .is_garbage = true,
            .is_negated = false,
            .variable = 111111111,
        },
    };

    std.debug.print("{d}\n", .{@sizeOf(MemoryCell)});
    assert(@sizeOf(MemoryCell) == 4);
    assert(cell.garbage.is_garbage);
    assert(cell.header.is_garbage);
    assert(cell.header.len == cell.garbage.len);
}
