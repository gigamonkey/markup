#!/usr/bin/env ruby -w
# encoding: UTF-8

require './markup'
require 'test/unit'

class TestMarkup < Test::Unit::TestCase

  def check_already_clean(input)
    check_clean input, input
  end

  def check_clean(input, expected, tabwidth=8)
    assert_equal expected, TextCleaner.new(tabwidth).clean(input).with_object('') { |c, s| s << c }
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

end
