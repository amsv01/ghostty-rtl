//! Bidirectional text helpers.
//!
//! This is not a full implementation of the Unicode Bidirectional
//! Algorithm (UAX #9). Terminals are a grid of cells and text is
//! written to the grid in logical order, so a full UAX #9
//! implementation doesn't map well onto the terminal model. Instead,
//! we classify codepoints by their strong directionality so that the
//! text shaper can segment runs by direction and shape RTL runs
//! (Arabic, Hebrew, Persian, etc.) properly. The renderer then
//! mirrors RTL runs within the cells they occupy.
//!
//! This gives correct results for the overwhelmingly common terminal
//! cases: pure RTL text, RTL text with embedded numbers, and LTR text
//! with embedded RTL words. It does not reorder runs at the line
//! level (e.g. a line starting with an RTL word will still begin at
//! the left edge of the grid).

const std = @import("std");

/// The strong directionality of a codepoint.
pub const Direction = enum {
    /// Left-to-right strong characters (Latin, Cyrillic, CJK, ...) and
    /// all weak/neutral characters (digits, spaces, punctuation, marks)
    /// which take on the direction of the surrounding text.
    ltr,

    /// Right-to-left strong characters: Arabic, Hebrew, Syriac,
    /// Thaana, NKo, and related scripts and presentation forms.
    rtl,
};

/// Returns the strong directionality of a codepoint.
///
/// Weak and neutral codepoints (numbers, spaces, punctuation,
/// combining marks, bidi controls) are reported as `.ltr` so that
/// they join whatever run they find themselves in; the run iterator
/// only breaks runs on strong characters.
pub fn direction(cp: u21) Direction {
    return if (isRtl(cp)) .rtl else .ltr;
}

/// True if the codepoint is a decimal digit, including digits from
/// RTL scripts (Arabic-Indic, Extended Arabic-Indic/Persian, NKo).
///
/// Digits have a weak bidi class (EN/AN): numbers are always laid out
/// left-to-right even inside RTL text. The shaper's run iterator uses
/// this to break digit sequences out of RTL runs so that all shapers
/// (including those without full bidi support) render numbers in the
/// correct order.
pub fn isDigit(cp: u21) bool {
    return switch (cp) {
        '0'...'9',
        0x0660...0x0669, // Arabic-Indic digits
        0x06F0...0x06F9, // Extended Arabic-Indic digits (Persian)
        0x07C0...0x07C9, // NKo digits
        => true,
        else => false,
    };
}

/// True if the codepoint is a strong RTL (R or AL bidi class) character.
///
/// The ranges below cover the RTL scripts in common use. Unassigned
/// codepoints within these blocks are included, which is harmless.
pub fn isRtl(cp: u21) bool {
    // Digits in RTL scripts have a weak bidi class (AN): numbers are
    // always laid out left-to-right even inside RTL text. We treat
    // them as neutral so they can be segmented out of RTL runs and
    // rendered in the correct order.
    if (isDigit(cp)) return false;

    return switch (cp) {

        // Hebrew
        0x0590...0x05FF,
        // Arabic
        0x0600...0x06FF,
        // Syriac
        0x0700...0x074F,
        // Arabic Supplement
        0x0750...0x077F,
        // Thaana
        0x0780...0x07BF,
        // NKo
        0x07C0...0x07FF,
        // Samaritan
        0x0800...0x083F,
        // Mandaic
        0x0840...0x085F,
        // Syriac Supplement
        0x0860...0x086F,
        // Arabic Extended-B
        0x0870...0x089F,
        // Arabic Extended-A
        0x08A0...0x08FF,
        // Hebrew Presentation Forms, Alphabetic Presentation Forms
        // (the RTL-compatible part of the block starts at FB1D)
        0xFB1D...0xFB4F,
        // Arabic Presentation Forms-A
        0xFB50...0xFDFF,
        // Arabic Presentation Forms-B
        0xFE70...0xFEFF,
        // Imperial Aramaic, Palmyrene, Nabataean, Hatran, Phoenician,
        // Lydian, and other historical RTL scripts.
        0x10800...0x10FFF,
        // Adlam
        0x1E900...0x1E95F,
        // Arabic Mathematical Alphabetic Symbols
        0x1EE00...0x1EEFF,
        => true,

        else => false,
    };
}

test "direction classification" {
    const testing = std.testing;

    // Strong LTR
    try testing.expectEqual(Direction.ltr, direction('a'));
    try testing.expectEqual(Direction.ltr, direction('Z'));
    try testing.expectEqual(Direction.ltr, direction(0x4E00)); // CJK

    // Weak/neutral report as LTR
    try testing.expectEqual(Direction.ltr, direction(' '));
    try testing.expectEqual(Direction.ltr, direction('5'));
    try testing.expectEqual(Direction.ltr, direction('.'));
    try testing.expectEqual(Direction.ltr, direction(0x200D)); // ZWJ

    // Arabic (Persian characters included)
    try testing.expectEqual(Direction.rtl, direction(0x0633)); // س
    try testing.expectEqual(Direction.rtl, direction(0x0644)); // ل
    try testing.expectEqual(Direction.rtl, direction(0x0627)); // ا
    try testing.expectEqual(Direction.rtl, direction(0x0645)); // م
    try testing.expectEqual(Direction.rtl, direction(0x067E)); // پ (peh, Persian)
    try testing.expectEqual(Direction.rtl, direction(0x06AF)); // گ (gaf, Persian)
    try testing.expectEqual(Direction.rtl, direction(0x0686)); // چ (cheh, Persian)
    try testing.expectEqual(Direction.rtl, direction(0x0698)); // ژ (jeh, Persian)
    try testing.expectEqual(Direction.rtl, direction(0x06CC)); // ی (Farsi yeh)
    try testing.expectEqual(Direction.rtl, direction(0x06A9)); // ک (keheh)

    // Hebrew
    try testing.expectEqual(Direction.rtl, direction(0x05D0)); // א

    // Digits in RTL scripts are weak, not strong RTL
    try testing.expectEqual(Direction.ltr, direction(0x06F2)); // ۲ Persian two
    try testing.expectEqual(Direction.ltr, direction(0x0665)); // ٥ Arabic-Indic five

    // isDigit
    try testing.expect(isDigit('7'));
    try testing.expect(isDigit(0x06F2)); // ۲
    try testing.expect(isDigit(0x0665)); // ٥
    try testing.expect(!isDigit(0x0633)); // س
    try testing.expect(!isDigit('a'));

    // Presentation forms
    try testing.expectEqual(Direction.rtl, direction(0xFEFB)); // lam-alef form
    try testing.expectEqual(Direction.rtl, direction(0xFB1D)); // Hebrew presentation
}
