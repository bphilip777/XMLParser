const std = @import("std");
const Data = @import("Data.zig");

const Match = @import("Match.zig");
const Carry = Match.Carry;
const bitIndexesOfTag = Match.bitIndexesOfTag;
const bitIndexesOfScalar = Match.bitIndexesOfScalar;

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

pub fn countTagsV(text: []const u8) u32 {
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

    return n_tags;
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

pub fn getTagsV(text: []const u8, tags: []Tag, spillover_tag: ?*Tag) void {
    if (text.len == 0) unreachable;
    if (tags.len == 0) unreachable;
    const TEXT_LEN: u32 = @truncate(text.len);
    // cases:
    // 0. normal - same number of open and close tags w/in 64 bits
    // 1. tag start on 1 64-bit and ends on another 64-bit
    // 2. close tag ahead of open tag b/c of rollover from previous text
    // 3. curr position + vector length > text length

    var i: u32 = 0;
    var carry_bit: ?u32 = null;
    var match: Match = undefined;
    match.carry = std.mem.zeroes(Carry);
    var tag_idx: u32 = 0;
    var is_first: bool = spillover_tag != null;

    while (i + VECTOR_LEN < TEXT_LEN) : (i += VECTOR_LEN) {
        match = bitIndexesOfTag(text[i .. i + VECTOR_LEN], match.carry);
        if (match.open_matches == 0 and match.close_matches == 0) continue;

        if (is_first) {
            std.debug.assert(@ctz(match.close_matches) < @ctz(match.open_matches));
            spillover_tag.?.*.end = i + @ctz(match.close_matches);
            match.close_matches = BitTricks.turnOffLastBit(u64, match.close_matches);
            is_first = false;
        }

        while (match.close_matches > 0) : (tag_idx += 1) {
            const open_bit = blk: {
                if (carry_bit) |bit| {
                    std.debug.assert(@ctz(match.open_matches) > @ctz(match.close_matches));
                    break :blk bit;
                } else {
                    break :blk i + @ctz(match.open_matches);
                }
            };
            if (carry_bit) |_| carry_bit = null;
            const close_bit = i + @ctz(match.close_matches);

            match.open_matches = BitTricks.turnOffLastBit(u64, match.open_matches);
            match.close_matches = BitTricks.turnOffLastBit(u64, match.close_matches);

            tags[tag_idx] = .{
                .start = open_bit,
                .end = close_bit,
            };
        }

        if (match.open_matches != 0) {
            std.debug.assert(@popCount(match.open_matches) == 1);
            carry_bit = i + @ctz(match.open_matches);
        }
    } else if (i != text.len) {
        var text_data: [VECTOR_LEN]u8 = undefined;
        @memcpy(text_data[0 .. text.len - i], text[i..text.len]);
        @memset(text_data[text.len - i .. VECTOR_LEN], 0);

        match = bitIndexesOfTag(&text_data, match.carry);
        if (match.open_matches == 0 and match.close_matches == 0) return;

        if (is_first) {
            std.debug.assert(@ctz(match.close_matches) < @ctz(match.open_matches));
            spillover_tag.?.*.end = i + @ctz(match.close_matches);
            match.close_matches = BitTricks.turnOffLastBit(u64, match.close_matches);
            is_first = false;
        }

        while (match.close_matches > 0) : (tag_idx += 1) {
            const open_bit = if (carry_bit) |bit| bit else i + @ctz(match.open_matches);
            carry_bit = null;
            const close_bit = i + @ctz(match.close_matches);

            match.open_matches = BitTricks.turnOffLastBit(u64, match.open_matches);
            match.close_matches = BitTricks.turnOffLastBit(u64, match.close_matches);

            tags[tag_idx] = .{
                .start = open_bit,
                .end = close_bit,
            };
        }

        if (match.open_matches != 0) {
            std.debug.assert(@popCount(match.open_matches) == 1);
            tags[tag_idx].start = i + @ctz(match.open_matches);
            carry_bit = null;
        }
    }

    if (carry_bit) |bit| {
        std.debug.assert(tag_idx == tags.len);
        std.debug.assert(tags[tag_idx].start == undefined);
        tags[tag_idx].start = bit;
    }
}

test "Vectorized Get Tags" {
    const allo = std.testing.allocator;
    // cases
    // 0. normal - same number of open and close tags, open tags precedes close tag, no intersects, all in 64 bytes
    // 1. tag start on 1 64-bit and ends on another 64-bit
    // 2. close tag before open tag b/c of rollover from previous text
    // 3. curr position + vector length > text length

    // var spillover_tags = [_]?*Tag{ null, null, .{ .start = 5, .end = undefined } };
    const texts = [_][]const u8{
        "<member><basic>Hello World</basic><name>Jeff</name><type>VkStruc",
        "<member><basic>Hello World</basic><name>Jeff</name><type>Vk<hello world>",
        "type><member><basic>Hello World</basic><name>Jeff</name><type>VkStru",
        "<member><basic>Hello World</basic><name>Jeff</name><type>",
    };

    const all_expected_starts = [_][]const u32{
        &.{ 0, 8, 26, 34, 44, 51 },
        &.{ 0, 8, 26, 34, 44, 51, 59 },
        &.{ 5, 13, 31, 39, 49, 56 },
        &.{ 0, 8, 26, 34, 44, 51 },
    };
    const all_expected_ends = [_][]const u32{
        &.{ 7, 14, 33, 39, 50, 56 },
        &.{ 7, 14, 33, 39, 50, 56, 71 },
        &.{ 12, 19, 38, 44, 55, 61 },
        &.{ 7, 14, 33, 39, 50, 56 },
    };
    var expected_spillover_tag: Tag = .{ .start = 0, .end = 4 };
    const all_expected_spillovers = [_]?*Tag{
        null,
        null,
        &expected_spillover_tag,
        null,
    };
    const all_expected_n_tags = [_]u32{ 6, 7, 6, 6 };
    var spillover_example: Tag = .{ .start = 0, .end = 0 };
    const spillover_tags = [texts.len]?*Tag{ null, null, &spillover_example, null };
    for (
        texts,
        all_expected_n_tags,
        spillover_tags,
        all_expected_starts,
        all_expected_ends,
        all_expected_spillovers,
    ) |
        text,
        expected_n_tags,
        spillover_tag,
        expected_starts,
        expected_ends,
        expected_spillover,
    | {
        // std.debug.print("Text: {s}\n", .{text});

        const n_tags = countTagsV(text);
        try std.testing.expectEqual(expected_n_tags, n_tags);
        // std.debug.print("# of Tags: {}\n", .{n_tags});

        const tags = try allo.alloc(Tag, n_tags);
        defer allo.free(tags);

        getTagsV(text, tags, spillover_tag);
        // for (tags) |tag| std.debug.print("{}\n", .{tag});
        for (tags, expected_starts, expected_ends) |tag, expected_start, expected_end| {
            try std.testing.expectEqual(tag.start, expected_start);
            try std.testing.expectEqual(tag.end, expected_end);
        }

        // std.debug.print("{?} {?}\n", .{ spillover_tag, expected_spillover });
        if (spillover_tag == null) {
            try std.testing.expectEqual(spillover_tag, expected_spillover);
        } else {
            try std.testing.expectEqual(spillover_tag.?.start, expected_spillover.?.start);
            try std.testing.expectEqual(spillover_tag.?.end, expected_spillover.?.end);
        }
        // std.debug.print("Spillover Tag: {?}\n", .{spillover_tag});
    }
}

fn countVWrapper(
    comptime char: u8,
    text: []const u8,
    n_chars: *u32,
    is_complete: *bool,
) void {
    if (text.len == 0) unreachable;
    n_chars.* = countScalarV(text, char);
    is_complete.* = true;
}

fn countTagsVWrapper(
    text: []const u8,
    n_tags: *u32,
    is_complete: *bool,
) void {
    if (text.len == 0) unreachable;
    n_tags.* = countTagsV(text);
    is_complete.* = true;
}

fn computeThreads(comptime EXPECTED_N_THREADS: u8, TEXT_LEN: u32, MIN_TEXT_CHUNK_SIZE: u8) u8 {
    if (EXPECTED_N_THREADS < 1 or EXPECTED_N_THREADS > 12) @compileError("1 <= # of Threads <= 12.");
    const N_CHUNKS: u32 = @as(u32, @truncate(TEXT_LEN / MIN_TEXT_CHUNK_SIZE)) + @as(u32, @intFromBool(@mod(TEXT_LEN, MIN_TEXT_CHUNK_SIZE) != 0));
    const n_threads: u8 = if (EXPECTED_N_THREADS < N_CHUNKS) EXPECTED_N_THREADS else @truncate(N_CHUNKS);
    return n_threads;
}

fn countT(
    comptime EXPECTED_N_THREADS: u8,
    text: []const u8,
    n_matches: *[EXPECTED_N_THREADS]u32,
) !void {
    if (EXPECTED_N_THREADS < 1 or EXPECTED_N_THREADS > 12) @compileError("1 <= # of Threads <= 12.");
    if (text.len == 0 or text.len > std.math.maxInt(u32)) unreachable;
    const MIN_TEXT_CHUNK_SIZE: u8 = 64;
    const n_threads = computeThreads(EXPECTED_N_THREADS, @truncate(text.len), MIN_TEXT_CHUNK_SIZE);

    const text_step: u32 = @max(MIN_TEXT_CHUNK_SIZE, @as(u32, @truncate(text.len / n_threads)));
    var is_complete = [_]bool{false} ** EXPECTED_N_THREADS;

    if (EXPECTED_N_THREADS > n_threads) @memset(is_complete[n_threads..EXPECTED_N_THREADS], true);
    const trues: @Vector(EXPECTED_N_THREADS, bool) = @splat(true);

    var text_start: u32 = 0;
    var threads: [EXPECTED_N_THREADS]std.Thread = undefined;
    for (0..n_threads - 1) |i| {
        threads[i] = try std.Thread.spawn(.{}, countTagsVWrapper, .{
            text[text_start .. text_start +% text_step],
            &n_matches[i],
            &is_complete[i],
        });
        text_start +%= text_step;
    } else {
        if (text_start != text.len) {
            threads[n_threads - 1] = try std.Thread.spawn(.{}, countTagsVWrapper, .{
                text[text_start..text.len],
                &n_matches[n_threads - 1],
                &is_complete[n_threads - 1],
            });
        }
    }

    for (threads[0..n_threads]) |thread| thread.detach();

    while (true) {
        const v = @as(@Vector(EXPECTED_N_THREADS, bool), is_complete);
        if (@reduce(.And, v == trues)) break;
    }
}

test "Count T" {
    const text = "<member><basic>Hello World</basic><name>Jeff</name><type>VkStruc<member><basic>Hello World</basic><name>Jeff</name><type>VkStruc<member><basic>Hello World</basic><name>Jeff</name><type>VkStruc";
    const n_threads: u8 = 4;
    var all_n_matches = [_]u32{0} ** n_threads;
    try countT(n_threads, text, &all_n_matches);
    const total_matches = @reduce(.Add, @as(@Vector(n_threads, u32), all_n_matches));
    const expected_total_matches: u8 = 18;
    try std.testing.expectEqual(expected_total_matches, total_matches);
}

pub fn getTagsT(comptime EXPECTED_N_THREADS: u8, allo: std.mem.Allocator, text: []const u8) !void { // ![]Tag {
    _ = allo;
    if (EXPECTED_N_THREADS == 0 or EXPECTED_N_THREADS > 12) @compileError("1 <= # of Threads <= 12.");
    if (text.len == 0 or text.len > std.math.maxInt(u32)) unreachable;

    const MIN_TEXT_CHUNK_SIZE: u8 = 64;
    const n_threads = computeThreads(EXPECTED_N_THREADS, @truncate(text.len), MIN_TEXT_CHUNK_SIZE);
    // var threads: [EXPECTED_N_THREADS]std.Thread = undefined;

    var is_complete = [_]bool{false} ** EXPECTED_N_THREADS;
    if (EXPECTED_N_THREADS > n_threads) @memset(is_complete[n_threads..EXPECTED_N_THREADS], true);

    const all_open_tags: [EXPECTED_N_THREADS]u32, const all_close_tags: [EXPECTED_N_THREADS]u32 = blk: {
        var all_open_tags = [_]u32{0} ** EXPECTED_N_THREADS;
        var all_close_tags = [_]u32{0} ** EXPECTED_N_THREADS;

        try countT(EXPECTED_N_THREADS, text, &all_open_tags);
        try countT(EXPECTED_N_THREADS, text, &all_close_tags);

        break :blk .{ all_open_tags, all_close_tags };
    };

    for (all_open_tags, all_close_tags) |open_tags, close_tags| {
        std.debug.print("{}-{}\n", .{ open_tags, close_tags });
    }

    // var spill_tags: [EXPECTED_N_THREADS]Tag = undefined;
    // var spillover_tags = [_]?*Tag{null} ** EXPECTED_N_THREADS;

    // @memset(is_complete[0..n_threads], false);

    const total_tags = @reduce(.Add, @as(@Vector(EXPECTED_N_THREADS, u32), all_open_tags));
    std.debug.print("Total # Of Tags: {}\n", .{total_tags});
    // const tags = try allo.alloc(Tag, total_tags);
    // errdefer allo.free(tags);
    //
    // var text_start: u32 = 0;
    // var tag_start: u32 = 0;
    // for (0..n_threads - 1) |i| {
    //     threads[i] = try std.Thread.spawn(.{}, getTagsV, .{
    //         text[text_start .. text_start +% text_step],
    //         tags[tag_start .. tag_start +% all_n_tags[i]],
    //         spillover_tag,
    //     });
    //     text_start +%= text_step;
    // } else {
    //     threads[i] = try std.Thread.spawn(.{}, getTagsV, .{
    //         text[text_start..text.len],
    //         tags[tag_start..tags.len],
    //         spillover_tag,
    //     });
    // }
    //
    // for (threads[0..n_threads]) |thread| thread.detach();
    //
    // while (true) {
    //     const v = @as(@Vector(EXPECTED_N_THREADS, bool), is_complete);
    //     if (@reduce(.And, v == trues)) break;
    // }
    //
    // return tags;
}

test "Get Tags T" {
    const allo = std.testing.allocator;

    const filename = "src/vk_extern_struct.xml";
    const data = try Data.init(allo, filename);
    defer data.deinit();
    std.debug.print("{s}", .{data.data});

    try getTagsT(12, allo, data.data);
}
