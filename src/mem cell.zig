const Literal = @import("literal.zig").Literal;
const ClauseHeader = @import("clause.zig").ClauseHeader;
const Garbage = @import("mem garbage.zig").GarbageHeader;

pub const MemoryCell = packed union {
    literal: Literal,
    header: ClauseHeader,
    garbage: Garbage,
    integer: u32,
};
