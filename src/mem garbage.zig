const memc = @import("mem cell.zig");
const GarbageFlag = memc.GarbageFlag;
const VariableFlag = memc.LiteralFlag;

pub const Garbage = packed struct {
    header: GarbageHeader,
    next: ?*Garbage,

    const Self = @This();

    pub fn fromCells(cell: [*]memc.MemoryCell) Garbage {
        return @ptrCast(cell);
    }

    /// returns n memory cells
    /// the first cell is a garbage header, that returns the amount of cells
    pub fn toCells(self: Self) [*]memc.MemoryCell {
        return @ptrCast(self);
    }
};

pub const GarbageHeader = packed struct {
    is_garbage: bool,

    /// the length of the garbage field
    /// in this case it is the amount of literals that could be stored, if the garbage was a clause
    len: u31,

    const Self = @This();
};
