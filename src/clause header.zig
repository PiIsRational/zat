const GarbageFlag = @import("mem cell.zig").GarbageFlag;
const VariableFlag = @import("mem cell.zig").VariableFlag;

pub const ClauseHeader = packed struct {
    is_garbage: GarbageFlag,
    is_variable: VariableFlag,
    len: u30,
};
