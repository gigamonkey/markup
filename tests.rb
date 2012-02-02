#!/usr/bin/env ruby -w
# encoding: UTF-8

require 'test/unit'
require_relative 'markup'

class TestMarkup < Test::Unit::TestCase

  def check_already_clean(input)
    check_clean input, input
  end

  def check_clean(input, expected, tabwidth=8)
    assert_equal expected, TextCleaner.new(tabwidth).clean(input).inject('') { |s, c| s << c.to_s }
  end

  def test_already_cleaner
    check_already_clean ""
    check_already_clean "abc"
    check_already_clean "abc\n\ndef"
    check_already_clean "abc\n\n\ndef"
    check_already_clean "abc    def"
  end

  def test_tab_conversion
    # Tabs
    check_clean "\tabc", "        abc"
    check_clean "\tabc", "    abc", tabwidth=4
    check_clean "\t\tabc", "    abc", tabwidth=2
    check_clean "abc\tefg", "abc        efg"
  end

  def test_trailing_whitespace
    check_clean "abc   \n", "abc\n"
    check_clean "abc    ", "abc"
    check_clean "abc\t", "abc"
    check_clean "abc  \t  \nefg", "abc\nefg"
  end

  def test_cr_conversion
    check_clean "abc\r\n", "abc\n"
    check_clean "abc\refg", "abc\nefg"
    check_clean "abc\r", "abc\n"
    check_clean "abc   \refg\r", "abc\nefg\n"
    check_clean "abc\r\n\r\nefg", "abc\n\nefg"
    # These next few are kind of screwy since they mix CRLFs with CRs.
    check_clean "abc\r\n\r\r", "abc\n\n\n"
    check_clean "abc\r\n\r\r\n", "abc\n\n\n"
    check_clean "abc\r\n\n\r\r\r\n", "abc\n\n\n\n\n"
    check_clean "abc\r\n\n\r\r\r\n\r", "abc\n\n\n\n\n\n"
  end

  def test_positions
    check_tokens("abc", ["a", "b", "c"], [0,0,0], [0,1,2])
    check_tokens("abc def",
                 ["a", "b", "c", " ", "d", "e", "f"],
                 [0, 0, 0, 0, 0, 0, 0],
                 [0, 1, 2, 3, 4, 5, 6])
    check_tokens("abc  def",
                 ["a", "b", "c", " ", " ", "d", "e", "f"],
                 [0, 0, 0, 0, 0, 0, 0, 0],
                 [0, 1, 2, 3, 4, 5, 6, 7])
    check_tokens("abc\nefg",
                 ["a", "b", "c", "\n", "e", "f", "g"],
                 [0,0,0,0,1,1,1],
                 [0,1,2,3,0,1,2])
    check_tokens("abc\refg",
                 ["a", "b", "c", "\n", "e", "f", "g"],
                 [0,0,0,0,1,1,1],
                 [0,1,2,3,0,1,2])
    check_tokens("abc\r\nefg",
                 ["a", "b", "c", "\n", "e", "f", "g"],
                 [0,0,0,0,1,1,1],
                 [0,1,2,3,0,1,2])
    check_tokens("abc\r\n\r\nefg",
                 ["a", "b", "c", "\n", "\n", "e", "f", "g"],
                 [0,0,0,0,1,2,2,2],
                 [0,1,2,3,0,0,1,2])
    check_tokens("abc   \nefg",
                 ["a", "b", "c", "\n", "e", "f", "g"],
                 [0, 0, 0, 0, 1, 1, 1],
                 [0, 1, 2, 6, 0, 1, 2])
  end

  def check_tokens(input, values, lines, columns)
    tokens = TextCleaner.new.clean(input).to_a
    assert_equal values, tokens.collect(&:value)
    assert_equal lines, tokens.collect(&:line)
    assert_equal columns, tokens.collect(&:column)
  end


end

class TestToken < Test::Unit::TestCase

  def test_equality
    assert_equal Token.new("a", 0, 0), Token.new("a", 0, 0)
    assert_equal Token.new("a", 0, 0), Token.new("a", 1, 2)
    assert_equal Token.new("a", 0, 0), "a"
    assert_equal Token.new(:blank, 0, 0), :blank
  end

  def test_inequality
    assert_not_equal Token.new("a", 0, 0), :a
    assert_not_equal Token.new(:blank, 0, 0), "blank"
    assert_not_equal Token.new("a", 0, 0), Token.new(:a, 0, 0)

    # Kind of too bad this doesn't work.
    assert_not_equal :blank, Token.new(:blank, 0, 0)
  end

end


class TestTokenizer < Test::Unit::TestCase

  def token_values(text)
    Tokenizer.new.tokens(TextCleaner.new.clean(text)).map(&:value).to_a
  end

  def test_newline
    assert_equal [], token_values("")
    assert_equal [:blank], token_values("\n")
    assert_equal ["a", "b", "c", :newline, "e", "f", "g", :blank], token_values("abc\nefg")
    assert_equal ["a", "b", "c", :newline, "e", "f", "g", :blank], token_values("abc\refg")
    assert_equal ["a", "b", "c", :newline, "e", "f", "g", :blank], token_values("abc\r\nefg")
    assert_equal ["a", "b", "c", :blank, "e", "f", "g", :blank], token_values("abc\n\nefg")

    assert_equal ["a", "b", "c", :blank, [:indent, 2], "e", "f", "g", :blank], token_values("abc\n\n  efg\n")
    assert_equal ["a", "b", "c", :blank, [:indent, 2], "e", "f", "g", :newline, "h", "i", "j", :blank], token_values("abc\n\n  efg\n  hij")
    assert_equal ["a", "b", "c", :blank, [:indent, 2], "e", "f", "g", :newline, "h", "i", "j", :blank, [:outdent, 2], "k", "l", "m", :blank], token_values("abc\n\n  efg\n  hij\n\nklm\n")
    assert_equal ["a", "b", "c", :blank, [:indent, 2], "e", "f", "g", :newline, "h", "i", "j", :blank, [:indent, 2], "k", "l", "m", :blank], token_values("abc\n\n  efg\n  hij\n\n    klm\n")
    assert_equal ["a", "b", "c", :blank, [:indent, 2], "e", "f", "g", :newline, [:indent, 2], "h", "i", "j", :blank, [:outdent, 4], "k", "l", "m", :blank], token_values("abc\n\n  efg\n    hij\n\nklm\n")
    assert_equal ["a", "b", "c", " ", " ", "e", "f", "g", :blank], token_values("abc  efg")
    assert_equal ["a", "b", "c", :newline, [:indent, 2], "e", " ", " ", "f", "g", :blank], token_values("abc\n  e  fg")

  end


end

class TestElement < Test::Unit::TestCase

  def test_just_text
    assert_equal "foo", Element.new(:p, "foo").just_text
    assert_equal "foobar", Element.new(:p, "foo", "bar").just_text
    assert_equal "foobar", Element.new(:p, "foo", Element.new(:i, "bar")).just_text
    assert_equal "foobarbaz", Element.new(:p, "foo", Element.new(:i, "bar"), "baz").just_text
    assert_equal "foobarbaz", Element.new(:p, "foo", Element.new(:i, "bar", Element.new(:b, "baz"))).just_text
  end

  def test_add_text
    e = Element.new(:p)
    assert_equal "", e.just_text
    e.add_text("foo")
    assert_equal "foo", e.just_text
    e.add_text("bar")
    assert_equal "foobar", e.just_text
  end

  def test_add_child
    e = Element.new(:p)
    assert_equal [], e.children
    e.add_child(Element.new(:i))
    assert_equal :i, e.children[0].tag
  end

  def test_each
    e = Element.from_array([:p, "foo", [:i, "bar"], "baz"])
    assert_equal e.each.to_a, e.children
  end


end
