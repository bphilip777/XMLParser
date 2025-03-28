const std = @import("std");
const Data = @import("Data.zig");

const Carry = @import("Match.zig").Carry;
const bitIndexesOfTag = @import("Match.zig").bitIndexesOfTag;
const bitIndexesOfScalar = @import("Match.zig").bitIndexesOfScalar;

const Tag = @This();
const BitTricks = @import("BitTricks");
const VECTOR_LEN: u8 = 64;

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

pub fn countTagsV(text: []const u8, num_tags: *u32) void {
    const TEXT_LEN: u32 = @truncate(text.len);
    var n_tags: u32 = 0;

    var i: u32 = 0;
    var carry = std.mem.zeroes(Carry);
    while (i + VECTOR_LEN < TEXT_LEN) : (i += VECTOR_LEN) {
        const match = bitIndexesOfTag(text[i .. i + VECTOR_LEN], carry);
        carry = match.carry;
        n_tags += @popCount(match.open_matches);
    }

    if (i != TEXT_LEN) {
        var text_data: [VECTOR_LEN]u8 = undefined;
        @memcpy(text_data[0 .. text.len - i], text[i..text.len]);
        @memset(text_data[text.len - i .. VECTOR_LEN], 0);

        const match = bitIndexesOfTag(&text_data, carry);
        carry = match.carry;
        n_tags += @popCount(match.open_matches);
    }

    num_tags.* = n_tags;
}

pub fn countScalarV(text: []const u8, comptime char: u8) u32 {
    const TEXT_LEN: u32 = @truncate(text.len);
    var n_tags: u32 = 0;

    var i: u32 = 0;
    var carry = std.mem.zeroes(Carry);
    while (i + VECTOR_LEN < TEXT_LEN) : (i += VECTOR_LEN) {
        const match = bitIndexesOfScalar(text[i .. i + VECTOR_LEN], char, carry);
        carry = match.carry;
        n_tags += @popCount(match.matches);
    }

    if (i != TEXT_LEN) {
        var text_data: [VECTOR_LEN]u8 = undefined;
        @memcpy(text_data[0 .. text.len - i], text[i..text.len]);
        @memset(text_data[text.len - i .. VECTOR_LEN], 0);

        const match = bitIndexesOfScalar(&text_data, char, carry);
        carry = match.carry;
        n_tags += @popCount(match.matches);
    }

    return n_tags;
}

test "Count Chars - Vectorized Version" {
    const text: []const u8 = "<member><basic>Hello World</basic><name>Jeff</name><type>VkStructureType</type></member>";

    const n_tags = countTagsV(text);
    const n_open = countScalarV(text, '<');
    const n_close = countScalarV(text, '>');

    try std.testing.expect(n_open == n_close);
    try std.testing.expect(n_open == 8);
    try std.testing.expect(n_tags == n_open);
}

pub fn getTagsV(text: []const u8, tags: []Tag) void {
    std.debug.assert(tags.len < std.math.maxInt(u32));
    const TEXT_LEN: u32 = @truncate(text.len);

    var i: u32 = 0;
    var carry: Carry = std.mem.zeroes(Carry);
    var tag_idx: u32 = 0;

    while (i + VECTOR_LEN < TEXT_LEN) : (i += VECTOR_LEN) {
        const match = bitIndexesOfTag(text[i .. i + VECTOR_LEN], carry);
        var open_matches = match.open_matches;
        var close_matches = match.close_matches;
        carry = match.carry;

        while (close_matches > 0) : (tag_idx += 1) {
            const open_bit = @ctz(open_matches);
            const close_bit = @ctz(close_matches);

            open_matches = BitTricks.turnOffLastBit(u64, open_matches);
            close_matches = BitTricks.turnOffLastBit(u64, close_matches);

            tags[tag_idx] = Tag{
                .start = i + open_bit,
                .end = i + close_bit,
            };
        }
    }

    if (i != TEXT_LEN) {
        var text_data: [VECTOR_LEN]u8 = undefined;
        @memcpy(text_data[0 .. TEXT_LEN - i], text[i..text.len]);
        @memset(text_data[TEXT_LEN - i .. VECTOR_LEN], 0);

        const match = bitIndexesOfTag(&text_data, carry);
        var open_matches = match.open_matches;
        var close_matches = match.close_matches;
        carry = match.carry;

        while (close_matches > 0) : (tag_idx += 1) {
            const open_bit = @ctz(open_matches);
            const close_bit = @ctz(close_matches);

            open_matches = BitTricks.turnOffLastBit(u64, open_matches);
            close_matches = BitTricks.turnOffLastBit(u64, close_matches);

            tags[tag_idx] = Tag{
                .start = i + open_bit,
                .end = i + close_bit,
            };
        }
    }
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

    const n_tags = countTagsV(text);
    try std.testing.expectEqual(n_tags, expected_tags.len);

    const tags = try allo.alloc(Tag, n_tags);
    defer allo.free(tags);
    var is_complete = false;
    getTagsV(text, tags, &is_complete);

    const expected_names = [_][]const u8{ "member", "basic", "basic", "name", "name", "type", "type", "member" };

    for (tags, expected_tags, expected_names) |tag, expected_tag, expected_name| {
        try std.testing.expectEqualDeep(expected_tag, tag);
        const actual_name = getTagName(text, tag);
        try std.testing.expectEqualStrings(expected_name, actual_name);
    }
}

pub fn getTagsT(allo: std.mem.Allocator, text: []const u8) !void { // []Tag {
    const N_THREADS: u8 = 12;
    const step = text.len / N_THREADS;
    var is_complete = [_]bool{false} ** N_THREADS;

    const n_tags = blk: {
        var n_tags = [_]u32{0} ** N_THREADS;
        var i: u8 = 0;

        inline while (i < N_THREADS) : (i += 1) {
            const start = i * step;
            const end = if (i == N_THREADS - 1) text.len else start + step;

            std.Thread.spawn(.{}, countTagsV, .{text[start..end]});
            n_tags[i] = countTagsV(text[start..end]);
        }
        break :blk n_tags;
    };

    const total_tags = @reduce(.Add, @as(@Vector(N_THREADS, u32), n_tags));

    const tags = try allo.alloc(Tag, total_tags);
    defer allo.free(tags);

    var is_thread_complete = [_]bool{false} ** N_THREADS;

    var i: u8 = 0;
    var tag_start: u32 = 0;
    inline while (i < N_THREADS) : ({
        i += 1;
        tag_start += n_tags[i];
    }) {
        const start = i * step;
        const end = if (i == N_THREADS - 1) text.len else start + step;

        getTagsV(text[start..end], tags[tag_start .. tag_start + n_tags[i]], &is_thread_complete[i]);
    }

    // i = 0;
    // inline while (i < N_THREADS) : (i += 1) {
    //     const start = i * step;
    //     const end = if (i == N_THREADS - 1) text.len else start + step;
    //
    //     getTagsV(text[start..end], , );
    // }

    // return tags;
}

test "Get Tags T" {
    const text: []const u8 = "<member><basic>Hello World</basic><name>Jeff</name><type>VkStructureType</type></member>";
    const allo = std.testing.allocator;
    // getTagsT(1, allo, text);

    // const expected_tags = [_]Tag{
    //     .{ .start = 0, .end = 7 },
    //     .{ .start = 8, .end = 14 },
    //     .{ .start = 26, .end = 33 },
    //     .{ .start = 34, .end = 39 },
    //     .{ .start = 44, .end = 50 },
    //     .{ .start = 51, .end = 56 },
    //     .{ .start = 72, .end = 78 },
    //     .{ .start = 79, .end = 87 },
    // };

    // const expected_tag_names = [_][]const u8{ "member", "basic", "basic", "name", "name", "type", "type", "member" };

    { // single thread works
        try getTagsT(allo, text);
        // const tags = try getTagsT(allo, text);
        // defer allo.free(tags);

        // for (expected_tags, tags) |expected_tag, tag| {
        //     try std.testing.expectEqual(tag.start, expected_tag.start);
        //     try std.testing.expectEqual(tag.end, expected_tag.end);
        // }
        //
        // for (expected_tag_names, tags) |expected_tag_name, tag| {
        //     const tag_name = getTagName(text, tag);
        //     try std.testing.expectEqualStrings(expected_tag_name, tag_name);
        // }
    }

    // { // Multiple Threads
    //     const tags = try getTagsT(2, allo, text);
    //     defer allo.free(tags);
    //
    //     for (expected_tags, tags) |expected_tag, tag| {
    //         try std.testing.expect(expected_tag.start == tag.start and expected_tag.end == tag.end);
    //     }
    //
    //     for (expected_tag_names, tags) |expected_tag_name, tag| {
    //         const tag_name = getTagName(text, tag);
    //         try std.testing.expectEqualStrings(expected_tag_name, tag_name);
    //     }
    // }
}
