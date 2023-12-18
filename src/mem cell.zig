const Literal = @import("literal.zig").Literal;
const ClauseHeader = @import("clause header.zig").ClauseHeader;
const Garbage = @import("mem garbage.zig").MemGarbage;

pub const VariableFlag = enum(u1) {
    OTHER,
    VARIABLE,
};

pub const GarbageFlag = enum(u1) {
    HEADER,
    GARBAGE,
};

pub const MemoryCell = packed union {
    variable: Literal,
    header: ClauseHeader,
    garbage: Garbage,
    integer: u32,
};
