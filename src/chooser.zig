const std = @import("std");
const Allocator = std.mem.Allocator;
const assert = std.debug.assert;
const expect = std.testing.expect;

const Chooser = @This();

heap_position: []Position,
scores: []f32,
var_heap: std.ArrayList(u32),
bump_val: f32 = 1,

const GROWTH: f32 = 1.1;
const MAX_BUMP: f32 = std.math.floatMax(f32) / 16;

pub fn init(gpa: Allocator, variables: usize) !Chooser {
    const vars = try gpa.alloc(Position, variables);
    const scores = try gpa.alloc(f32, variables);
    @memset(scores, 0);

    var heap = std.ArrayList(u32).init(gpa);
    try heap.ensureTotalCapacity(variables);

    for (vars, 0..) |*variable, i| {
        variable.val = @intCast(i);
        try heap.append(@intCast(i));
    }

    return .{
        .scores = scores,
        .heap_position = vars,
        .var_heap = heap,
    };
}

pub fn len(self: Chooser) usize {
    return self.var_heap.items.len;
}

fn scaleBack(self: *Chooser) void {
    const scale = 1 / self.bump_val;
    self.bump_val = 1;

    for (self.scores) |*score| score.* *= scale;
}

pub fn bump(self: *Chooser, variable: u32) void {
    const score = &self.scores[variable];
    score.* += self.bump_val;
    if (score.* >= MAX_BUMP) self.scaleBack();

    const position = self.heap_position[variable];
    if (position.eql(.invalid)) return;

    self.bubbleUp(variable);
}

pub fn grow(self: *Chooser) void {
    self.bump_val *= GROWTH;
    if (self.bump_val >= MAX_BUMP) self.scaleBack();
}

pub fn append(self: *Chooser, variable: u32) !void {
    const pos = self.heap_position[variable];
    if (!pos.eql(.invalid)) return;

    const new_pos: Position = .{ .val = @intCast(self.var_heap.items.len) };
    self.heap_position[variable] = new_pos;
    try self.var_heap.append(variable);

    self.bubbleUp(variable);
}

pub fn bubbleUp(self: *Chooser, variable: u32) void {
    while (true) {
        const curr_pos = self.heap_position[variable].val;
        if (curr_pos == 0) return;

        const parent_pos = (curr_pos - 1) / 2;
        const parent_var = self.var_heap.items[parent_pos];

        if (self.scores[variable] <= self.scores[parent_var]) return;

        std.mem.swap(
            Position,
            &self.heap_position[variable],
            &self.heap_position[parent_var],
        );

        std.mem.swap(
            u32,
            &self.var_heap.items[curr_pos],
            &self.var_heap.items[parent_pos],
        );
    }
}

pub fn nextVar(self: *Chooser) ?u32 {
    if (self.var_heap.items.len == 0) return null;

    const out = self.var_heap.swapRemove(0);
    self.heap_position[out] = .invalid;
    const heap = self.var_heap.items;

    if (heap.len != 0) {
        self.heap_position[heap[0]].val = 0;
        self.sinkDown(heap[0]);
    }

    return out;
}

pub fn sinkDown(self: *Chooser, variable: u32) void {
    while (true) {
        const curr_pos = self.heap_position[variable].val;

        const left_child = curr_pos * 2 + 1;
        const right_child = curr_pos * 2 + 2;

        const heap = self.var_heap.items;

        var best_score = self.scores[variable];
        var best_var = variable;
        var best_pos = curr_pos;

        if (left_child < heap.len) {
            const left_var = heap[left_child];
            const left_score = self.scores[left_var];

            if (left_score > best_score) {
                best_score = left_score;
                best_var = left_var;
                best_pos = left_child;
            }
        }

        if (right_child < heap.len) {
            const right_var = heap[right_child];
            const right_score = self.scores[right_var];

            if (right_score > best_score) {
                best_score = right_score;
                best_var = right_var;
                best_pos = right_child;
            }
        }

        if (best_var == variable) return;

        std.mem.swap(
            Position,
            &self.heap_position[variable],
            &self.heap_position[best_var],
        );

        std.mem.swap(u32, &heap[curr_pos], &heap[best_pos]);
    }
}

pub fn deinit(self: Chooser) void {
    const allocator = self.var_heap.allocator;
    self.var_heap.deinit();
    allocator.free(self.heap_position);
    allocator.free(self.scores);
}

const Position = struct {
    const invalid_val = std.math.maxInt(u32);
    pub const invalid: Position = .{ .val = invalid_val };

    val: u32 = invalid_val,

    pub fn eql(self: Position, other: Position) bool {
        return self.val == other.val;
    }
};

test "inout" {
    const gpa = std.testing.allocator;
    const vars = 10;
    var chooser = try Chooser.init(gpa, vars);
    defer chooser.deinit();

    for (0..vars) |variable| {
        for (0..variable) |_| chooser.bump(@intCast(variable));
        //chooser.grow();
    }

    var i: usize = 9;
    while (chooser.nextVar()) |variable| {
        try expect(variable == i);
        i -%= 1;
    }

    for (0..vars) |variable| try chooser.append(@intCast(variable));

    i = 9;
    while (chooser.nextVar()) |variable| {
        try expect(variable == i);
        i -%= 1;
    }
}
