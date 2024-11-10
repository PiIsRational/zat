const std = @import("std");
const Allocator = std.mem.Allocator;
const fs = std.fs;

const SatInstance = @import("sat_instance.zig").SatInstance;
const Clause = @import("clause.zig").Clause;
const Variable = @import("variable.zig").Variable;
const Literal = @import("literal.zig").Literal;
const ClauseDb = @import("clause_db.zig").ClauseDb;
const BinClauses = @import("binary_clauses.zig").BinClauses;
const Impl = @import("impl.zig").Impl;

const BUFFER_SIZE = 10000;

pub const InstanceBuilder = struct {
    literal_list: std.ArrayList(Literal),
    lit_counts: []usize,
    sat_type: SatData,
    clause_num: usize,
    satisfiable: bool,
    allocator: Allocator,

    const Self = @This();

    pub fn loadFromFile(allocator: Allocator, path: []const u8) !SatInstance {
        const stdout = std.io.getStdOut().writer();
        var reader = try fs.cwd().openFile(path, .{});
        const buffer = try allocator.alloc(u8, BUFFER_SIZE);
        defer allocator.free(buffer);
        var characters = try reader.read(buffer);
        var index: usize = 0;
        var currline = std.ArrayList(u8).init(allocator);
        defer currline.deinit();
        var self = InstanceBuilder{
            .literal_list = std.ArrayList(Literal).init(allocator),
            .satisfiable = true,
            .allocator = allocator,
            .sat_type = undefined,
            .lit_counts = undefined,
            .clause_num = 0,
        };
        defer self.deinit();

        var instance: SatInstance = undefined;

        while (index < characters) {
            switch (buffer[index]) {
                '\n' => {
                    try self.parseLine(currline, &instance);
                    currline.clearRetainingCapacity();
                },
                else => try currline.append(buffer[index]),
            }

            index += 1;
            if (index == BUFFER_SIZE) {
                index = 0;
                characters = try reader.read(buffer);
            }
        }

        if (self.clause_num < self.sat_type.clause_count) {
            try self.parseLine(currline, &instance);
        }

        // wrong clause count
        if (self.clause_num != self.sat_type.clause_count) {
            try stdout.print("(ERROR) Illegal Clause Count!\n", .{});
            return ParseError.IllegalClauseCount;
        }

        try instance.watch.setUp(instance.clauses);

        return instance;
    }

    fn parseLine(
        self: *InstanceBuilder,
        line: std.ArrayList(u8),
        instance: *SatInstance,
    ) !void {
        const stdout = std.io.getStdOut().writer();

        if (line.items.len == 0) {
            try self.parseClause(line, instance);
            return;
        }

        switch (line.items[0]) {
            'c' => {},
            'p' => {
                try self.parseP(line);
                instance.* = try SatInstance
                    .init(self.allocator, self.sat_type.variable_count);
                self.lit_counts = try self.allocator
                    .alloc(usize, self.sat_type.variable_count * 2);

                try stdout.print(
                    "c Parsed a SAT instance with {d} variables and {d} clauses.\n",
                    .{ self.sat_type.variable_count, self.sat_type.clause_count },
                );
            },
            else => try self.parseClause(line, instance),
        }
    }

    fn parseClause(
        self: *InstanceBuilder,
        line: std.ArrayList(u8),
        instance: *SatInstance,
    ) !void {
        if (instance.clauseCount() == self.sat_type.clause_count) return;

        self.literal_list.clearRetainingCapacity();
        var parsing_num = false;
        var current_num: u30 = 1;
        var neg: bool = false;
        for (line.items) |character| {
            if (parsing_num and isWhitespace(character)) {
                parsing_num = false;
                if (current_num > instance.variables.impls.len) {
                    std.debug.print("found a disallowed: {d}\n", .{current_num});
                    return ParseError.NonExistingVariableRef;
                }

                if (current_num == 0) break;

                try self.literal_list.append(Literal.init(neg, current_num - 1));
                current_num = 1;
                neg = false;
            }

            if (parsing_num) {
                if (!isNum(character)) {
                    std.debug.print("found a disallowed: ({c})\n", .{character});
                    return ParseError.NotaDigit;
                }

                current_num *= 10;
                current_num += @intCast(character - '0');
            }

            if (!parsing_num and (character == '-' or isNum(character))) {
                parsing_num = true;

                if (character == '-') {
                    neg = true;
                    current_num = 0;
                } else {
                    current_num = @intCast(character - '0');
                }
            }

            if (!parsing_num and !isWhitespace(character)) {
                std.debug.print("found a disallowed: {c}\n", .{character});
                return ParseError.UnexpectedCharacter;
            }
        }

        self.clause_num += 1;
        const literals = self.trivialSimpl(self.literal_list.items);

        if (self.triviallyTrue(literals)) return;
        try instance.addClause(literals);
    }

    fn isWhitespace(character: u8) bool {
        return character == ' ' or character == '\t' or character == '\r';
    }

    fn isNum(character: u8) bool {
        return character >= '0' and character <= '9';
    }

    fn parseP(self: *InstanceBuilder, line: std.ArrayList(u8)) !void {
        if (!std.mem.eql(u8, line.items[0..5], "p cnf")) return ParseError.IllegalHeader;

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
                if (isNum(char)) {
                    parsing = true;
                    num_start = i;
                } else if (!isWhitespace(char)) {
                    return ParseError.UnexpectedCharacter;
                }
            } else if (parsing and isWhitespace(char)) {
                if (parsing_var_count) {
                    var_count = try std.fmt.parseInt(usize, line.items[num_start..i], 0);
                    parsing_var_count = false;
                } else {
                    clause_count = try std.fmt.parseInt(usize, line.items[num_start..i], 0);
                    break;
                }
                parsing = false;
            } else if (parsing and !isNum(char)) {
                return ParseError.NotaDigit;
            }

            if (parsing and i == end - 1) {
                clause_count = try std.fmt.parseInt(usize, line.items[num_start..end], 0);
                if (parsing_var_count) return ParseError.UnknownFormat;
            }
        }

        if (parsing_var_count) return ParseError.UnknownFormat;

        self.sat_type = .{ .variable_count = var_count, .clause_count = clause_count };
    }

    /// Removes doubled literals from clauses.
    fn trivialSimpl(self: *Self, literals: []Literal) []Literal {
        @memset(self.lit_counts, 0);
        var i: usize = 0;
        var end: usize = literals.len;

        while (i < end) : (i += 1) {
            const current = literals[i].toIndex();
            if (self.lit_counts[current] == 1) {
                literals[i] = literals[end - 1];
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
        if (literals.len == 0) return true;
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
