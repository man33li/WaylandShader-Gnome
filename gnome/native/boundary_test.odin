package waylandshader

import "core:testing"

@(test)
argument_utf8_bom :: proc(t: ^testing.T) {
    cases := [?]struct { source: cstring, expected: string }{
        {"", ""},
        {"GAIN", "GAIN"},
        {"\xef\xbb\xbf", ""},
        {"\xef\xbb\xbfGAIN", "GAIN"},
        {"\xef\xbb\xbf\xef\xbb\xbfGAIN", "\xef\xbb\xbfGAIN"},
        {"GA\xef\xbb\xbfIN", "GA\xef\xbb\xbfIN"},
        {"\xef\xbb\xbf/a.slangp", "/a.slangp"},
        {"\xef\xbb\xbf[]", "[]"},
    }
    for c in cases {
        actual, err := text(c.source)
        testing.expect(t, err==nil)
        testing.expect_value(t, actual, c.expected)
    }
    invalid := [?]cstring{nil, "\xff", "\xef\xbb\xbf\xff", "\xef\xbb", "\xc0\xaf"}
    for source in invalid {
        actual, err := text(source)
        testing.expect_value(t, actual, "")
        testing.expect_value(t, error_message(err), "Invalid UTF-8 argument")
    }
}
