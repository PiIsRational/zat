const memc = @import("mem cell.zig");
const GarbageFlag = memc.GarbageFlag;
const VariableFlag = memc.VariableFlag;

pub const MemGarbage = packed struct {
    is_garbage: GarbageFlag,
    is_variable: VariableFlag,

    /// the length of the garbage field
    len: u30,
};
