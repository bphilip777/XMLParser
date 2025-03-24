const std = @import("std");
const Data = @import("Data.zig");
const Tag = @This();
const BitTricks = @import("BitTricks");

start: u32,
end: u32,

pub fn getTagName(data: []const u8, tag: Tag) []const u8 {
    if (data[tag.start] != '<') unreachable;
    var start: usize = tag.start + 1;
    while (true) : (start += 1) {
        switch (data[start]) {
            'a'...'z', 'A'...'Z' => break,
            ' ', '/' => {},
            else => unreachable,
        }
    }

    var end: usize = start;
    while (true) : (end += 1) {
        switch (data[end]) {
            '>', ' ' => break,
            '\'', '\"' => end = skipComment(usize, data, end),
            else => {},
        }
    }

    return data[start..end];
}

test "Get Tag Name" {
    const tags = [_][]const u8{ "<tag>", "</tag>", "<type category=\"struct\" name=\"VkInstanceCreateInfo\">" };
    const exp_names = [_][]const u8{ "tag", "tag", "type" };
    for (tags, exp_names) |tag, exp_name| {
        const tag_name = getTagName(tag, .{ .start = 0, .end = @truncate(tag.len) });
        try std.testing.expectEqualStrings(exp_name, tag_name);
    }
}

pub fn tagNamesMatch(data: []const u8, tag1: Tag, tag2: Tag) bool {
    const tag1_name = getTagName(data, tag1);
    const tag2_name = getTagName(data, tag2);
    return std.mem.eql(u8, tag1_name, tag2_name);
}

test "Tag Names Match" {
    const data = [_][]const u8{ "<tag></tag>", "<type category=\"struct\" name=\"VkInstanceCreateInfo\"></type>" };
    const tag1s = [_]Tag{ .{ .start = 0, .end = 4 }, .{ .start = 0, .end = 44 } };
    const tag2s = [_]Tag{ .{ .start = 5, .end = 10 }, .{ .start = 52, .end = 58 } };
    for (data, tag1s, tag2s) |datum, tag1, tag2| {
        try std.testing.expect(tagNamesMatch(datum, tag1, tag2));
    }
}

fn skipComment(comptime T: type, data: []const u8, i: T) T {
    var j: T = i + 1;
    const char = data[i];
    while (true) : (j += 1) {
        if (data[j] == char) break;
    }
    return j;
}

pub fn count(comptime T: type, text: []const u8, char: u8) T {
    var n_found: T = 0;

    var i: T = 0;
    while (i < text.len) : (i += 1) {
        const ch = text[i];
        if (ch == '\'' or ch == '\"') {
            i = skipComment(T, text, i);
            continue;
        }
        n_found += @intFromBool(ch == char);
    }

    return n_found;
}

test "Count Tags" {
    const T: type = u16;
    const text: []const u8 = "<member><basic>Hello World</basic><name>Jeff</name><type>VkStructureType</type></member>";
    const n_open = count(T, text, '<');
    const n_close = count(T, text, '>');
    try std.testing.expect(n_open == n_close);
    try std.testing.expect(n_open == 8);
}

pub fn getTags(allo: std.mem.Allocator, data: []const u8) !std.ArrayList(Tag) {
    var tags = std.ArrayList(Tag).initCapacity(allo, 1_024) catch unreachable;

    var found_prolog: bool = false;
    var found_open: bool = false;

    var i: usize = 0;
    var j: usize = 0;

    while (true) : (i += 1) {
        if (i == data.len) break;
        switch (data[i]) {
            '<' => {
                if (found_open) std.log.err("On open, did not end previous tag: position: {}\n", .{i});
                const tag_type: TagType = getTagType(data, .{ .start = @truncate(i), .end = undefined });

                switch (tag_type) {
                    .prolog => {
                        if (found_prolog) std.log.err("On prolog, found more than 1: position: {}\n", .{i});
                        found_prolog = true;
                    },
                    else => {},
                }

                try tags.append(.{
                    .start = @truncate(i),
                    .end = undefined,
                });
                found_open = true;
            },
            '>' => {
                if (!found_open) std.log.err("On close, did not end previous tag: positon: {}\n", .{i});
                tags.items[j].end = @truncate(i);
                if (tags.items[j].end < tags.items[j].start) std.log.err("Tag: {} has end < start\n", .{i});
                found_open = false;
                j += 1;
            },
            '\'', '\"' => {
                i = skipComment(data, i);
            },
            else => {},
        }
    }

    return tags;
}

pub fn getTagType(data: []const u8, tag: Tag) TagType {
    return switch (data[tag.start + 1]) {
        '?' => .prolog,
        '/' => .close,
        'a'...'z', 'A'...'Z' => .open,
        else => unreachable,
    };
}

test "Get Tag Type" {
    const names = [_][]const u8{ "<name>", "</name>", "<?xml>" };
    const values = [_]TagType{ .open, .close, .prolog };
    for (names, values) |name, value| {
        const tag_type = getTagType(name, .{ .start = 0, .end = @truncate(name.len) });
        try std.testing.expect(tag_type == value);
    }
}

pub fn writeTags(
    allo: std.mem.Allocator,
    data: []const u8,
    filename: []const u8,
    tags: *const std.ArrayList(Tag),
) !void {
    const file = try std.fs.cwd().createFile(filename, .{});
    defer file.close();

    for (tags.items) |tag| {
        const line = try std.fmt.allocPrint(allo, "{s}\n", .{data[tag.start .. tag.end + 1]});
        defer allo.free(line);
        _ = file.write(line) catch unreachable;
    }
}

pub inline fn printTag(data: []const u8, tag: Tag) void {
    std.debug.print("{s}\n", .{data[tag.start .. tag.end + 1]});
}

pub fn printTags(data: []const u8, tags: []const Tag) void {
    for (tags) |tag| {
        printTag(data, tag);
    }
}

pub const TagType = enum {
    prolog,
    open,
    close,
};

pub fn countV(comptime T: type, text: []const u8, char: u8) T {
    // assumes no intersections b/w quotes, only subsets (one pair of quotes w/in another) or independent (no overlap)
    var n_found: T = 0;

    const LEN: u32 = @truncate(text.len);

    const VECTOR_LENGTH: u32 = 64;
    const V: type = @Vector(VECTOR_LENGTH, u8);
    const v: V = @splat(char);
    const s: V = @splat('\'');
    const d: V = @splat('\"');

    var squote_carry: bool = false;
    var dquote_carry: bool = false;

    var i: u32 = 0;
    while (i + VECTOR_LENGTH < LEN) : (i += VECTOR_LENGTH) {
        const data_vector: V = @as(V, text[i..][0..VECTOR_LENGTH].*);

        var matches = @as(u64, @bitCast(v == data_vector));

        var squote_matches = @as(u64, @bitCast(data_vector == s));
        squote_matches, squote_carry = blk: {
            const bt = BitTricks.turnOnBitsBW2Bits(u64, squote_matches, squote_carry);
            break :blk .{ bt.mask, bt.carry };
        };

        var dquote_matches = @as(u64, @bitCast(data_vector == d));
        dquote_matches, dquote_carry = blk: {
            const bt = BitTricks.turnOnBitsBW2Bits(u64, dquote_matches, dquote_carry);
            break :blk .{ bt.mask, bt.carry };
        };

        matches &= ~squote_matches;
        matches &= ~dquote_matches;

        n_found += @popCount(matches);
    }

    if (i != LEN) {
        var data = [_]u8{0} ** VECTOR_LENGTH;
        @memcpy(data[0 .. text.len - i], text[i..text.len]);
        const data_vector: V = @as(V, data);

        var matches = @as(u64, @bitCast(v == data_vector));

        var squote_matches = @as(u64, @bitCast(data_vector == s));
        squote_matches, squote_carry = blk: {
            const bt = BitTricks.turnOnBitsBW2Bits(u64, squote_matches, squote_carry);
            break :blk .{ bt.mask, bt.carry };
        };

        var dquote_matches = @as(u64, @bitCast(data_vector == d));
        dquote_matches, dquote_carry = blk: {
            const bt = BitTricks.turnOnBitsBW2Bits(u64, dquote_matches, dquote_carry);
            break :blk .{ bt.mask, bt.carry };
        };

        matches &= ~squote_matches;
        matches &= ~dquote_matches;

        n_found += @popCount(matches);
    }

    return n_found;
}

test "Count Tags - Vectorized Version" {
    const T: type = u16;
    const text: []const u8 = "<member><basic>Hello World</basic><name>Jeff</name><type>VkStructureType</type></member>";
    const n_open = countV(T, text, '<');
    const n_close = countV(T, text, '>');
    try std.testing.expect(n_open == n_close);
    try std.testing.expect(n_open == 8);
}

pub fn getTagsV(allo: std.mem.Allocator, text: []const u8) !std.ArrayList(Tag) {
    // Vectorized Version of get Tags
    // assumes no intersection b/w quotes - only subsets or independent quotes (i.e. '""' or ''"", no '"'")
    // assumes '<' precedes '>', all independent, no subsets (i.e. no <<>>, only <><>)
    const n_tags = countV(u32, text, '<');
    var tags = try std.ArrayList(Tag).initCapacity(allo, n_tags);

    const LEN: u32 = @truncate(text.len);

    // vectors
    const VECTOR_LENGTH: u8 = 64;
    const V: type = @Vector(VECTOR_LENGTH, u8);
    const o: V = @splat('<');
    const c: V = @splat('>');
    const s: V = @splat('\'');
    const d: V = @splat('\"');

    // flags
    var open_carry: bool = false;
    var open_position: u32 = 0;

    var squote_carry: bool = false;
    var dquote_carry: bool = false;

    var i: u32 = 0;
    while (i + VECTOR_LENGTH < LEN) : (i += VECTOR_LENGTH) {
        const data_vector: V = @as(V, text[i..][0..VECTOR_LENGTH].*);

        // matches are in bitreverse order already
        var open_matches = @as(u64, @bitCast(o == data_vector));
        var close_matches = @as(u64, @bitCast(c == data_vector));
        var squote_matches = @as(u64, @bitCast(s == data_vector));
        var dquote_matches = @as(u64, @bitCast(d == data_vector));

        // turn quote matches into masks
        squote_matches, squote_carry = blk: {
            const bt = BitTricks.turnOnBitsBW2Bits(u64, squote_matches, squote_carry);
            break :blk .{ bt.mask, bt.carry };
        };

        dquote_matches, dquote_carry = blk: {
            const bt = BitTricks.turnOnBitsBW2Bits(u64, dquote_matches, dquote_carry);
            break :blk .{ bt.mask, bt.carry };
        };

        // remove matches within masks
        open_matches &= ~squote_matches;
        close_matches &= ~squote_matches;

        open_matches &= ~dquote_matches;
        close_matches &= ~dquote_matches;

        if (open_carry) {
            if (close_matches == 0) continue;

            const c_bit = @ctz(close_matches);
            close_matches = BitTricks.turnOffLastBit(u64, close_matches);
            try tags.append(.{
                .start = open_position,
                .end = i + c_bit,
            });

            open_carry = false;
        }

        // assume all open matches precede close matches + no open carry + no intersections of open and close carries
        while (close_matches > 0) {
            const o_bit = @ctz(open_matches);
            const c_bit = @ctz(close_matches);

            open_matches = BitTricks.turnOffLastBit(u64, open_matches);
            close_matches = BitTricks.turnOffLastBit(u64, close_matches);

            try tags.append(.{
                .start = i + o_bit,
                .end = i + c_bit,
            });
        }

        if (open_matches > 0) {
            open_carry = true;
            open_position = i + @ctz(open_matches);
        }
    }

    if (i != LEN) {
        var data = [_]u8{0} ** VECTOR_LENGTH;
        @memcpy(data[0 .. text.len - i], text[i..text.len]);
        const data_vector: V = @as(V, data);

        // matches are in bitreverse order already
        var open_matches = @as(u64, @bitCast(o == data_vector));
        var close_matches = @as(u64, @bitCast(c == data_vector));
        var squote_matches = @as(u64, @bitCast(s == data_vector));
        var dquote_matches = @as(u64, @bitCast(d == data_vector));

        // turn quote matches into masks
        squote_matches, squote_carry = blk: {
            const bt = BitTricks.turnOnBitsBW2Bits(u64, squote_matches, squote_carry);
            break :blk .{ bt.mask, bt.carry };
        };

        dquote_matches, dquote_carry = blk: {
            const bt = BitTricks.turnOnBitsBW2Bits(u64, dquote_matches, dquote_carry);
            break :blk .{ bt.mask, bt.carry };
        };

        // remove matches within masks
        open_matches &= ~squote_matches;
        close_matches &= ~squote_matches;

        open_matches &= ~dquote_matches;
        close_matches &= ~dquote_matches;

        if (open_carry) {
            const c_bit = @ctz(close_matches);
            close_matches = BitTricks.turnOffLastBit(u64, close_matches);
            try tags.append(.{
                .start = open_position,
                .end = i + c_bit,
            });

            open_carry = false;
        }

        // assume all open matches precede close matches + no open carry + no intersections of open and close carries
        while (close_matches > 0) {
            const o_bit = @ctz(open_matches);
            const c_bit = @ctz(close_matches);

            open_matches = BitTricks.turnOffLastBit(u64, open_matches);
            close_matches = BitTricks.turnOffLastBit(u64, close_matches);

            try tags.append(.{
                .start = i + o_bit,
                .end = i + c_bit,
            });
        }
    }

    return tags;
}

test "Vectorized Get Tags" {
    const allo = std.testing.allocator;
    const text: []const u8 = "<member><basic>Hello World</basic><name>Jeff</name><type>VkStructureType</type></member>";

    const expected_tags = [8]Tag{
        .{ .start = 0, .end = 7 },
        .{ .start = 8, .end = 14 },
        .{ .start = 26, .end = 33 },
        .{ .start = 34, .end = 39 },
        .{ .start = 44, .end = 50 },
        .{ .start = 51, .end = 56 },
        .{ .start = 72, .end = 78 },
        .{ .start = 79, .end = 87 },
    };
    const tags = try getTagsV(allo, text);
    defer tags.deinit();

    const expected_names = [_][]const u8{ "member", "basic", "basic", "name", "name", "type", "type", "member" };

    for (tags.items, expected_tags, expected_names) |tag, expected_tag, expected_name| {
        try std.testing.expectEqualDeep(expected_tag, tag);
        const actual_name = getTagName(text, tag);
        try std.testing.expectEqualStrings(expected_name, actual_name);
    }
}

// pub fn getTagsThreaded(allo: std.mem.Allocator, text: []const u8) !std.ArrayList(Tag) {
//     // vectorized + threaded version of getTags
//     const n_tags = countV(u32, text, '<');
//
//     var tags = try std.ArrayList(Tag).initCapacity(allo, n_tags);
//     defer tags.deinit();
//
//     const N_THREADS = 8;
//     inline for (0..N_THREADS) |i| {
//         std.Thread.spawn(.{}, , args: anytype);
//     }
// }
