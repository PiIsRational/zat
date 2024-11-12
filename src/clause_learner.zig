const std = @import("std");
const assert = std.debug.assert;
const Allocator = std.mem.Allocator;
const Clause = @import("clause.zig").Clause;
const Literal = @import("literal.zig").Literal;
const Conflict = @import("impl.zig").Conflict;
const SatInstance = @import("sat_instance.zig").SatInstance;

const ClauseLearner = @This();

literals: std.ArrayList(Literal),
set: std.DynamicBitSet,

// the amount of literals that have then `choice_count` of the instance
// in the learned clause
instance_choice_count_lits: usize,

/// initializes the clause learner (`size` is the amount of variables in the instance)
pub fn init(gpa: Allocator, size: usize) !ClauseLearner {
    return .{
        .literals = std.ArrayList(Literal).init(gpa),
        .set = try std.DynamicBitSet.initEmpty(gpa, size),
        .instance_choice_count_lits = 0,
    };
}

/// learns a new clause from the conflict
///
/// returns the lowest `choice_count` at which the clause asserts
pub fn learn(self: *ClauseLearner, conflict: Conflict, instance: *SatInstance) !usize {
    assert(self.literals.items.len == 0);

    // learn the empty clause (the conflict was at level 0 which means trivially unsat)
    if (instance.choice_count == 0) return 0;

    switch (conflict) {
        .binary => |bin| for (bin) |lit| try self.appendLit(lit, instance),
        .other => |clause| for (clause.getLiterals(instance.clauses)) |lit| {
            try self.appendLit(lit, instance);
        },
    }

    // resolve the clause with it's reason as long as
    // there is more than one literal of the current level.
    // (in reverse chronological order)

    var iter = std.mem.reverseIterator(instance.setting_order.items);
    while (iter.next()) |variable| {
        const lit = instance.variables.getLit(variable);
        if (!self.set.isSet(lit.toVar())) continue;

        self.set.unset(lit.toVar());
        self.instance_choice_count_lits -= 1;

        // check if lit is the last literal of the current choice
        if (self.instance_choice_count_lits == 0) {
            try self.literals.append(lit.negated());
            const lits = self.literals.items;

            // as lit is the first literal in the clause that will be unset
            // we need to put it first to not destroy watch invariants
            std.mem.swap(Literal, &lits[0], &lits[lits.len - 1]);
            break;
        } else switch (instance.variables.getReason(lit.toVar()).*) {
            .unary => {},
            .binary => |cause| try self.appendLit(cause, instance),
            .other => |clause| for (clause.getLiterals(instance.clauses)) |cause| {
                if (cause.eql(lit)) continue;
                try self.appendLit(cause, instance);
            },
        }
    }

    // iterate through all literals which are not of the current choice
    // (which excludes only the first) as they are still set in the set
    for (self.literals.items[1..]) |lit| self.set.unset(lit.toVar());
    assert(self.set.findFirstSet() == null);

    const lits = self.literals.items;
    if (lits.len < 2) return 0;
    const second = &lits[1];
    var max_choice_count = instance.variables.getChoiceCount(second.toVar()).*;

    for (lits[2..]) |*lit| {
        const choice_count = instance.variables.getChoiceCount(lit.toVar()).*;
        if (max_choice_count >= choice_count) continue;

        max_choice_count = choice_count;
        std.mem.swap(Literal, lit, second);
    }

    instance.chooser.grow();

    return max_choice_count;
}

fn appendLit(self: *ClauseLearner, lit: Literal, instance: *SatInstance) !void {
    const choice_count = instance.variables.getChoiceCount(lit.toVar()).*;
    if (choice_count == 0 or self.set.isSet(lit.toVar())) return;
    self.set.set(lit.toVar());
    instance.chooser.bump(@intCast(lit.toVar()));

    if (choice_count == instance.choice_count) {
        // add the literal only virtually and not to the clause
        // as it will be removed anyways
        self.instance_choice_count_lits += 1;
    } else {
        try self.literals.append(lit);
    }
}

pub fn clear(self: *ClauseLearner) void {
    self.literals.clearRetainingCapacity();
    self.instance_choice_count_lits = 0;
    assert(self.set.findFirstSet() == null);
}

pub fn deinit(self: ClauseLearner) void {
    self.set_in_set.deinit();
    self.literals.deinit();
    self.set.deinit();
}
