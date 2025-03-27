const std = @import("std");
const BitTricks = @import("BitTricks");
const VECTOR_LEN: u8 = 64;

pub const Carry = packed struct(u8) {
    single: bool = false,
    double: bool = false,
    backtick: bool = false,
    _pad: u5 = 0,
};

const Match = @This();

open_matches: u64,
close_matches: u64,
carry: Carry,

pub fn bitIndexesOfTag(text: []const u8, carry: Carry) Match {
    std.debug.assert(text.len == VECTOR_LEN);

    // vectors
    const V: type = @Vector(VECTOR_LEN, u8);
    const o: V = @splat('<');
    const c: V = @splat('>');
    const s: V = @splat('\'');
    const d: V = @splat('\"');
    const b: V = @splat('`');

    const data_vector: V = @as(V, text[0..][0..VECTOR_LEN].*);

    // matches are in bitreverse order - may be a problem
    var tag_matches = [_]u64{
        @as(u64, @bitCast(o == data_vector)),
        @as(u64, @bitCast(c == data_vector)),
    };

    var carry_matches = [3]u64{
        @as(u64, @bitCast(s == data_vector)),
        @as(u64, @bitCast(d == data_vector)),
        @as(u64, @bitCast(b == data_vector)),
    };

    var ret_carry = std.mem.zeroes(Carry);

    inline for (0..carry_matches.len, comptime std.meta.fieldNames(Carry)[0..3]) |i, field_name| {
        carry_matches[i], @field(ret_carry, field_name) = blk: {
            const bt = BitTricks.turnOnBitsBWPairsOfBits(u64, .{ .mask = carry_matches[i], .carry = @field(carry, field_name) });
            break :blk .{ bt.mask, bt.carry };
        };

        inline for (0..tag_matches.len) |j| {
            tag_matches[j] &= ~carry_matches[i];
        }
    }

    return .{
        .open_matches = tag_matches[0],
        .close_matches = tag_matches[1],
        .carry = ret_carry,
    };
}

test "Bit Indexes Of Tag" {
    const text: []const u8 = "<member><basic>Hello World</basic><name>Jeff</name><type>VkStructureType</type></member>";
    const matches = bitIndexesOfTag(text[0..VECTOR_LEN], std.mem.zeroes(Carry));

    var open_matches: u64 = matches.open_matches;
    var close_matches: u64 = matches.close_matches;

    const expected_open_matches = [_]u64{ 0, 8, 26, 34, 44, 51 };
    const expected_close_matches = [_]u64{ 7, 14, 33, 39, 50, 56 };

    var open_match: usize = 0;
    for (expected_open_matches) |expected_open_match| {
        open_match = @ctz(open_matches);
        try std.testing.expectEqual(expected_open_match, open_match);
        open_matches = BitTricks.turnOffLastBit(u64, open_matches);
    }

    var close_match: usize = 0;
    for (expected_close_matches) |expected_close_match| {
        close_match = @ctz(close_matches);
        try std.testing.expectEqual(expected_close_match, close_match);
        close_matches = BitTricks.turnOffLastBit(u64, close_matches);
    }

    try std.testing.expect(@as(u8, @bitCast(matches.carry)) == 0);
}

test "bitIndexesOfTag with single and double quotes carries" {
    const texts = [_][]const u8{
        "<member>'<basic>'Hello World\"</basic>\"<name>Jeff</name><type>VkStructureType</type></member>",
        "<member><basic>\'Hello World\"</basic>\"<name>Jeff</name><type>VkStructureType</type></member>",
        "<member><basic>Hello World\"</basic><name>Jeff</name><type>VkStructureType</type></member>",
    };

    const etn1 = [_][]const u8{ "member", "name", "/name", "type" };
    const etn2 = [_][]const u8{ "name", "/name", "type" };
    const etn3 = [_][]const u8{ "/basic", "name", "/name", "type" };
    const all_expected_tag_names = [_][]const []const u8{ &etn1, &etn2, &etn3 };

    const carries = [_]Carry{
        std.mem.zeroes(Carry),
        Carry{ .single = true },
        Carry{ .double = true },
    };

    for (0..3) |j| {
        const text = texts[j];
        const carry = carries[j];
        const expected_tag_names = all_expected_tag_names[j];

        const matches = bitIndexesOfTag(text[0..VECTOR_LEN], carry);

        try std.testing.expect(carry == carries[j]);

        var open_matches: u64 = matches.open_matches;
        var close_matches: u64 = matches.close_matches;
        var i: u8 = 0;
        while (open_matches > 0) : (i += 1) {
            const open_match = @ctz(open_matches);
            const close_match = @ctz(close_matches);

            try std.testing.expectEqualStrings(expected_tag_names[i], text[open_match + 1 .. close_match]);

            open_matches = BitTricks.turnOffLastBit(u64, open_matches);
            close_matches = BitTricks.turnOffLastBit(u64, close_matches);
        }
    }
}

const CustomMatch = struct {
    matches: u64,
    carry: Carry,
};

pub fn bitIndexesOfScalar(text: []const u8, comptime match_symbol: u8, carry: Carry) CustomMatch {
    // Same as above except now you can choose what characters to match on - still skips quotes
    std.debug.assert(text.len == VECTOR_LEN);

    // vectors
    const V: type = @Vector(VECTOR_LEN, u8);
    const match_vector: V = @splat(match_symbol);

    const s: V = @splat('\'');
    const d: V = @splat('\"');
    const b: V = @splat('`');

    const data_vector: V = @as(V, text[0..VECTOR_LEN].*);

    var matches = @as(u64, @bitCast(match_vector == data_vector));

    var carry_matches = [3]u64{
        @as(u64, @bitCast(s == data_vector)),
        @as(u64, @bitCast(d == data_vector)),
        @as(u64, @bitCast(b == data_vector)),
    };

    var ret_carry = std.mem.zeroes(Carry);

    inline for (0..carry_matches.len, comptime std.meta.fieldNames(Carry)[0..3]) |i, field_name| {
        carry_matches[i], @field(ret_carry, field_name) = blk: {
            const bt = BitTricks.turnOnBitsBWPairsOfBits(u64, .{ .mask = carry_matches[i], .carry = @field(carry, field_name) });
            break :blk .{ bt.mask, bt.carry };
        };

        matches &= ~carry_matches[i];
    }

    return .{
        .matches = matches,
        .carry = ret_carry,
    };
}
