#!/usr/bin/env ruby -w
# encoding: UTF-8

require 'test/unit'
require 'json'
require_relative 'markup'

class TestMarkup < Test::Unit::TestCase

  def assert_already_clean(input)
    assert_clean input, input
  end

  def assert_clean(input, expected, tabwidth=8)
    tokens = TextCleaner.new(tabwidth).clean(input)
    assert_equal expected, tokens.inject('') { |s, t| s << (t.is_a?(Token) ? t.text : t) }
  end

  def test_already_cleaner
    assert_already_clean ""
    assert_already_clean "abc"
    assert_already_clean "abc\n\ndef"
    assert_already_clean "abc\n\n\ndef"
    assert_already_clean "abc    def"
  end

  def test_tab_conversion
    # Tabs
    assert_clean "\tabc", "        abc"
    assert_clean "\tabc", "    abc", tabwidth=4
    assert_clean "\t\tabc", "    abc", tabwidth=2
    assert_clean "abc\tefg", "abc        efg"
  end

  def test_trailing_whitespace
    assert_clean "abc   \n", "abc\n"
    assert_clean "abc    ", "abc"
    assert_clean "abc\t", "abc"
    assert_clean "abc  \t  \nefg", "abc\nefg"
  end

  def test_cr_conversion
    assert_clean "abc\r\n", "abc\n"
    assert_clean "abc\refg", "abc\nefg"
    assert_clean "abc\r", "abc\n"
    assert_clean "abc   \refg\r", "abc\nefg\n"
    assert_clean "abc\r\n\r\nefg", "abc\n\nefg"
    # These next few are kind of screwy since they mix CRLFs with CRs.
    assert_clean "abc\r\n\r\r", "abc\n\n\n"
    assert_clean "abc\r\n\r\r\n", "abc\n\n\n"
    assert_clean "abc\r\n\n\r\r\r\n", "abc\n\n\n\n\n"
    assert_clean "abc\r\n\n\r\r\r\n\r", "abc\n\n\n\n\n\n"
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

    #assert_equal ["a", "b", "c", :blank, [:indent, 2], "e", "f", "g", :blank, [:outdent, 2]], token_values("abc\n\n  efg\n")
    #assert_equal ["a", "b", "c", :blank, [:indent, 2], "e", "f", "g", :newline, "h", "i", "j", :blank, [:outdent, 2]], token_values("abc\n\n  efg\n  hij")
    #assert_equal ["a", "b", "c", :blank, [:indent, 2], "e", "f", "g", :newline, "h", "i", "j", :blank, [:outdent, 2], "k", "l", "m", :blank], token_values("abc\n\n  efg\n  hij\n\nklm\n")
    #assert_equal ["a", "b", "c", :blank, [:indent, 2], "e", "f", "g", :newline, "h", "i", "j", :blank, [:indent, 2], "k", "l", "m", :blank, [:outdent, 4]], token_values("abc\n\n  efg\n  hij\n\n    klm\n")
    #assert_equal ["a", "b", "c", :blank, [:indent, 2], "e", "f", "g", :newline, [:indent, 2], "h", "i", "j", :blank, [:outdent, 4], "k", "l", "m", :blank], token_values("abc\n\n  efg\n    hij\n\nklm\n")
    assert_equal ["a", "b", "c", " ", " ", "e", "f", "g", :blank], token_values("abc  efg")
    #assert_equal ["a", "b", "c", :newline, [:indent, 2], "e", " ", " ", "f", "g", :blank, [:outdent, 2]], token_values("abc\n  e  fg")

  end

  def test_indent
    #assert_equal [[:indent, 2], "a", :blank,  [:outdent, 2]], token_values("  a")
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

  def assert_from_to_array(a)
    assert_equal a, Element.from_array(a).to_a, "a: #{a}"
  end

  def test_from_to_array
    assert_from_to_array [:body]
    assert_from_to_array [:body, [:p, "foo"]]
    assert_from_to_array [:body, [:p, "foo"]]
    assert_from_to_array [:body, [:p, "foo"], [:p, "bar"]]
  end
end


class TestFiles < Test::Unit::TestCase

  def json_to_array(json)
    convert_array(JSON.parse(File.open(json).read))
  end

  def convert_array(a)
    tag, *rest = a
    [tag.to_sym, *rest.map { |c| c.is_a?(String) ? c : convert_array(c) }]
  end

  def test_files
    Dir.glob("./tests/*.json") do |json|
      dir     = File.dirname(json)
      base    = File.basename(json, ".json")
      expect  = json_to_array(json)
      subdocs = Set.new([:note, :comment])
      #puts "Testing #{dir}/#{base}.txt"
      begin
        got = Markup.new(subdocs).parse_file("#{dir}/#{base}.txt").to_a
        assert_equal expect, got, "Error in test file #{base}"
      rescue Exception => e
        assert false, "Exception #{e.message} parsing test file #{base}\n#{e.backtrace}"
      end
    end
  end

end
