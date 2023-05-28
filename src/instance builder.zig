const Allocator = std.mem.Allocator;
const SatInstance = @import("sat instance.zig").SatInstance;
const Clause = @import("sat instance.zig").Clause;
const VarState = @import("sat instance.zig").VarState;
const Helper = @import("helper.zig");

const std = @import("std");
const fs = std.fs;
const BUFFER_SIZE = 10000;

pub const InstanceBuilder = struct {
    sat_type: SatData,

    pub fn load_from_file(allocator: Allocator, path: []const u8) !SatInstance {
        var reader = try fs.cwd().openFile(path, .{});
        var buffer = try allocator.alloc(u8, BUFFER_SIZE);
        var characters = try reader.read(buffer);
        var index: usize = 0;
        var currline = std.ArrayList(u8).init(allocator);
        var self = InstanceBuilder{
            .sat_type = undefined,
        };

        while (index < characters) {
            switch (buffer[index]) {
                '\n' => {
                    try self.parse_line(currline);
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

        return SatInstance{
            .allocator = allocator,
            .clauses = std.ArrayList(Clause).init(allocator),
            .variables = try allocator.alloc(VarState, 0),
        };
    }

    fn parse_line(self: *InstanceBuilder, line: std.ArrayList(u8)) !void {
        const stdout = std.io.getStdOut().writer();
        switch (line.items[0]) {
            'c' => {},
            'p' => {
                try self.parse_p(line);
                try stdout.print(
                    "this is an sat instance with {d} variables and {d} clauses.\n",
                    .{ self.sat_type.variable_count, self.sat_type.clause_count },
                );
            },
            else => try Helper.print_list(line),
        }
    }

    fn parse_p(self: *InstanceBuilder, line: std.ArrayList(u8)) !void {
        if (!std.mem.eql(u8, line.items[0..6], "p cnf ")) {
            return ParseError.IllegalHeader;
        }

        var var_count: usize = undefined;
        var clause_count: usize = undefined;
        var space_place: usize = undefined;
        var found_space = false;
        var end: usize = undefined;
        if (line.items[line.items.len - 1] == '\r') {
            end = line.items.len - 1;
        } else {
            end = line.items.len;
        }

        for (line.items[6..line.items.len], 6..) |char, i| {
            if (char == ' ') {
                var_count = try std.fmt.parseInt(usize, line.items[6..i], 0);
                space_place = i;
                found_space = true;
            } else if (char != '\r' and (char < '0' or char > '9')) {
                return ParseError.NotaDigit;
            }
        }

        clause_count = try std.fmt.parseInt(usize, line.items[(space_place + 1)..end], 0);

        self.sat_type = SatData{
            .variable_count = var_count,
            .clause_count = clause_count,
        };
    }

    const ParseError = error{
        IllegalHeader,
        NotaDigit,
    };
};

const SatData = struct {
    variable_count: usize,
    clause_count: usize,
};
