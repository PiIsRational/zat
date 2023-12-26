const Allocator = std.mem.Allocator;
const SatInstance = @import("sat instance.zig").SatInstance;
const Clause = @import("clause.zig").Clause;
const Variable = @import("variable.zig").Variable;
const Literal = @import("literal.zig").Literal;
const ClauseDb = @import("clause db.zig").ClauseDb;
const BinClauses = @import("binary clauses.zig").BinClauses;
const Helper = @import("helper.zig");

const std = @import("std");
const fs = std.fs;
const BUFFER_SIZE = 10000;

pub const InstanceBuilder = struct {
    literal_list: std.ArrayList(Literal),
    lit_counts: []usize,
    sat_type: SatData,
    clause_num: usize,
    satisfiable: bool,
    allocator: Allocator,

    const Self = @This();

    pub fn load_from_file(allocator: Allocator, path: []const u8) !SatInstance {
        const stdout = std.io.getStdOut().writer();
        var reader = try fs.cwd().openFile(path, .{});
        var buffer = try allocator.alloc(u8, BUFFER_SIZE);
        defer allocator.free(buffer);
        var characters = try reader.read(buffer);
        var index: usize = 0;
        var currline = std.ArrayList(u8).init(allocator);
        defer currline.deinit();
        var self = InstanceBuilder{
            .literal_list = std.ArrayList(Literal).init(allocator),
            .satisfyable = true,
            .allocator = allocator,
            .sat_type = undefined,
            .lit_counts = undefined,
            .clause_num = 0,
        };
        defer self.deinit();

        var instance: SatInstance = undefined;
        defer instance.watch.setUp(instance.clauses);

        while (index < characters) {
            switch (buffer[index]) {
                '\n' => {
                    try self.parse_line(
                        currline,
                        &instance,
                    );
                    currline.clearRetainingCapacity();
                },
                else => {
                    try currline.append(buffer[index]);
                },
            }

            index += 1;
            if (index == BUFFER_SIZE) {
                index = 0;
                characters = try reader.read(buffer);
            }
        }

        if (instance.clauseCount() < self.sat_type.clause_count) {
            try self.parse_line(
                currline,
                &instance,
            );
        }

        // wrong clause count
        if (instance.clauseCount() != self.sat_type.clause_count) {
            try stdout.print("(ERROR) Illegal Clause Count!", .{});
            return ParseError.IllegalClauseCount;
        }

        try stdout.print("printing the clauses of the instance:\n", .{});
        try stdout.print("{s}\n", .{instance});

        return instance;
    }

    fn parse_line(
        self: *InstanceBuilder,
        line: std.ArrayList(u8),
        instance: *SatInstance,
    ) !void {
        const stdout = std.io.getStdOut().writer();

        if (line.items.len == 0) {
            try self.parse_clause(
                line,
                instance,
            );
            return;
        }

        switch (line.items[0]) {
            'c' => {},
            'p' => {
                try self.parse_p(line);
                instance.* = try SatInstance.init(self.allocator, self.sat_type.variable_count);
                self.lit_counts = try self.allocator.alloc(usize, self.sat_type.variable_count * 2);
                @memset(instance.variables, .UNASSIGNED);

                try stdout.print(
                    "c Parsed a SAT instance with {d} variables and {d} clauses.\n",
                    .{ self.sat_type.variable_count, self.sat_type.clause_count },
                );
            },
            else => try self.parse_clause(
                line,
                instance,
            ),
        }
    }

    fn parse_clause(
        self: *InstanceBuilder,
        line: std.ArrayList(u8),
        instance: *SatInstance,
    ) !void {
        if (instance.clauseCount() == self.sat_type.clause_count) {
            return;
        }

        self.literal_list.clearRetainingCapacity();
        var parsing_num = false;
        var current_num: u30 = 1;
        var neg: bool = false;
        for (line.items) |character| {
            if (parsing_num and is_whitespace(character)) {
                parsing_num = false;
                if (current_num > instance.variables.len) {
                    std.debug.print("found a disallowed: {d}\n", .{current_num});
                    return ParseError.NonExistingVariableRef;
                }

                if (current_num == 0) {
                    break;
                }

                try self.literal_list.append(Literal.init(
                    neg,
                    current_num - 1,
                ));

                current_num = 1;
                neg = false;
            }

            if (parsing_num) {
                if (!is_num(character)) {
                    std.debug.print("found a disallowed: ({c})\n", .{character});
                    return ParseError.NotaDigit;
                }

                current_num *= 10;
                current_num += @intCast(character - '0');
            }

            if (!parsing_num and (character == '-' or is_num(character))) {
                parsing_num = true;

                if (character == '-') {
                    neg = true;
                    current_num = 0;
                } else {
                    current_num = @intCast(character - '0');
                }
            }

            if (!parsing_num and !is_whitespace(character)) {
                std.debug.print("found a disallowed: {c}\n", .{character});
                return ParseError.UnexpectedCharacter;
            }
        }

        var literals = self.trivialSimpl(self.literal_list.items);
        if (self.triviallyTrue(literals)) {
            return;
        }

        // unit clause
        if (literals.len == 1) {
            var lit = literals[0];

            if (!instance.set(
                lit.variable,
                if (lit.is_negated) .FORCE_FALSE else .FORCE_TRUE,
            )) {
                // there was a collision in the settings of the unit clauses
                // the clause cannot be satisfiable
                self.satisfiable = false;
            }

            return;
        }

        // binary clause
        if (literals.len == 2) {
            try instance.binary_clauses.addBinary(literals[0], literals[1]);
            return;
        }

        // normal clause
        try instance.clauses.addClause(literals);
    }

    fn is_whitespace(character: u8) bool {
        return character == ' ' or character == '\t' or character == '\r';
    }

    fn is_num(character: u8) bool {
        return character >= '0' and character <= '9';
    }

    fn parse_p(self: *InstanceBuilder, line: std.ArrayList(u8)) !void {
        if (!std.mem.eql(u8, line.items[0..5], "p cnf")) {
            return ParseError.IllegalHeader;
        }

        var var_count: usize = undefined;
        var clause_count: usize = undefined;

        var num_start: usize = 0;

        var end: usize = undefined;
        var parsing = false;
        var parsing_var_count = true;

        if (line.items[line.items.len - 1] == '\r') {
            end = line.items.len - 1;
        } else {
            end = line.items.len;
        }

        for (line.items[6..end], 6..) |char, i| {
            if (!parsing) {
                if (is_num(char)) {
                    parsing = true;
                    num_start = i;
                } else if (!is_whitespace(char)) {
                    return ParseError.UnexpectedCharacter;
                }
            } else if (parsing and is_whitespace(char)) {
                if (parsing_var_count) {
                    var_count = try std.fmt.parseInt(usize, line.items[num_start..i], 0);
                    parsing_var_count = false;
                } else {
                    clause_count = try std.fmt.parseInt(usize, line.items[num_start..i], 0);
                    break;
                }
                parsing = false;
            } else if (parsing and !is_num(char)) {
                return ParseError.NotaDigit;
            }

            if (parsing and i == end - 1) {
                clause_count = try std.fmt.parseInt(usize, line.items[num_start..end], 0);
                if (parsing_var_count) {
                    return ParseError.UnknownFormat;
                }
            }
        }

        if (parsing_var_count) {
            return ParseError.UnknownFormat;
        }

        self.sat_type = SatData{
            .variable_count = var_count,
            .clause_count = clause_count,
        };
    }

    /// Removes doubled literals from clauses.
    fn trivialSimpl(self: *Self, literals: []Literal) []Literal {
        @memset(self.lit_counts, 0);
        var i: usize = 0;
        var end: usize = literals.len;

        while (i < end) : (i += 1) {
            var current = literals[i].toIndex();
            if (self.lit_counts[current] == 1) {
                literals[i] = literals[end];
                end -= 1;
            } else {
                self.lit_counts[current] = 1;
            }
        }

        return literals[0..end];
    }

    /// Checks if a Clause is trivially true.
    ///
    /// (it contains the negated and non negated literal of a variable)
    fn triviallyTrue(self: *Self, literals: []Literal) bool {
        if (literals.len == 0) {
            return true;
        }

        @memset(self.lit_counts, 0);

        for (literals) |lit| {
            if (self.lit_counts[lit.negated().toIndex()] == 1) {
                return true;
            } else {
                self.lit_counts[lit.toIndex()] = 1;
            }
        }

        return false;
    }

    fn deinit(self: *Self) void {
        self.allocator.free(self.lit_counts);
        self.literal_list.deinit();
    }

    const ParseError = error{
        UnknownFormat,
        IllegalClauseCount,
        UnexpectedCharacter,
        NonExistingVariableRef,
        IllegalHeader,
        NotaDigit,
    };
};

const SatData = struct {
    variable_count: usize,
    clause_count: usize,
};
