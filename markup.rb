#!/usr/bin/env ruby -w
# encoding: UTF-8

#
# A Token represents a character or a slightly abstracted element of a
# text (e.g. :newline, :blankline, etc.) along with its starting
# position in the original text. A Token can be compared for equality
# with a plain character as long as the token is on the left-hand
# side.
#

class Token

  attr_reader :line, :column, :value

  def initialize(value, line, column)
    @value  = value
    @line   = line
    @column = column
  end

  def to_s
    @value.to_s
  end

  def ==(other)
    self.value == if other.respond_to? :value then other.value else other end
  end

end

class Element

  attr_reader :tag, :children

  def Element.from_array(array)
    tag, *rest = array
    Element.new(tag, *rest.map { |c| c.is_a?(Array) ? Element.from_array(c) : c })
  end

  def initialize(tag, *children)
    @tag      = tag
    @children = children
  end

  def each(&block)
    @children.each(&block)
  end

  def add_text(text)
    if @children[-1].is_a?(String)
      @children[-1] << text
    else
      add_child(text)
    end
  end

  def add_child(child)
    @children.push(child)
  end

  def just_text
    @children.inject('') { |text, c| text << (c.is_a?(Element) ? c.just_text : c.to_s) }
  end

  def to_s
    "(#{self.tag} #{self.children.inject('') { |s, t| s << t.to_s }})"
  end

  def to_a
    [@tag, *@children.map { |c| c.is_a?(Element) ? c.to_a : c }]
  end

end

#
# TextCleaner is responsible for converting tabs to spaces and
# removing trailing whitespace from lines. The TextCleaner#clean
# method iterates over tokens representing the characters in the text
# with some of them removed or replaced by other characters.
#
class TextCleaner

  def initialize(tabwidth=8)
    @tabwidth = tabwidth
  end

  def clean(text)
    if block_given?

      whitespace = ''
      afterCR    = false
      line       = 0
      column     = 0

      text.chars.each do |c|

        if afterCR
          # Either the CR was bare so we convert it to a LF or it was
          # part of a CRLF which also gets converted to a LF.
          whitespace = ''
          yield Token.new("\n", line, column)
          line += 1
          column = 0
        end

        if (afterCR && c != "\n") or !afterCR
          if c == "\t" or c == " "
            whitespace += c
          elsif c == "\n"
            column += whitespace.length
            whitespace = ''
            yield Token.new("\n", line, column)
            line += 1
            column = 0
          elsif c != "\r"
            whitespace.chars do |c|
              if c == " "
                yield Token.new(c, line, column)
              elsif c == "\t"
                @tabwidth.times { yield Token.new(" ", line, column) }
              end
              column += 1
            end
            whitespace = ''
            yield Token.new(c, line, column)
            column += 1
          end
        end

        afterCR = c == "\r"
      end

      # Last character was a bare CR
      if afterCR then yield "\n" end
    else
      Enumerator.new(self, :clean, text)
    end
  end
end

class Tokenizer

  def tokens(input_tokens)

    newlines            = 0
    newline_position    = nil
    current_indentation = 0
    leading_spaces      = false
    previous_token      = nil

    if block_given?
      input_tokens.each do |t|
        if t == "\n"
          if newlines == 0 then newline_position = [t.line, t.column] end
          newlines += 1
        else
          if newlines > 0
            yield Token.new(newlines == 1 ? :newline : :blank, *newline_position)
            newlines = 0
            leading_spaces = 0
          end
          if leading_spaces
            if t == " "
              leading_spaces += 1
            else
              if leading_spaces > current_indentation
                yield Token.new([:indent, leading_spaces - current_indentation], t.line, 0)
              elsif current_indentation > leading_spaces
                yield Token.new([:outdent, current_indentation - leading_spaces], t.line, 0)
              end
              current_indentation = leading_spaces
              leading_spaces = false
              yield t
            end
          else
            yield t
          end
        end
        previous_token = t
      end
      # Always yield a :blank at the end of file unless it was empty.
      if previous_token
        yield Token.new(:blank, previous_token.line, previous_token.column)
      end
    else
      Enumerator.new(self, :tokens, input_tokens)
    end
  end
end

class Parser
  def initialize(markup)
    @markup = markup
  end
end

class DocumentParser < Parser

  def grok(token)
    case token.value
    when :blank
    when :newline
      raise "Parse error #{token}"
    else
      p = @markup.open_element(:p)
      p.add_text(token.value)
      @markup.push_parser(ParagraphParser.new(@markup, p))
    end
  end
end

class ParagraphParser < Parser

  def initialize(markup, p)
    super(markup)
    @p = p
  end

  def grok(token)
    case token.value
    when :blank
      @markup.close_element(@p)
    when :newline
      @p.add_text(' ')
    else
      @p.add_text(token.value)
    end
  end
end

class Markup

  def initialize(tabwidth=8)
    @cleaner   = TextCleaner.new(tabwidth)
    @tokenizer = Tokenizer.new
    @elements  = []
    @parsers   = []
  end

  #
  # Parse the named file, which should be encoded in UTF-8
  #
  def parse_file(file)
    File.open(file, "r:UTF-8") { |f| parse(f) }
  end

  #
  # Parse the given string.
  #
  def parse_text(text)
    parse(text.encoding == 'UTF-8' ? text : text.encode('UTF-8'))
  end

  #
  # Parse any text that responds to the chars method.
  #
  def parse(text)
    tokens = @tokenizer.tokens(@cleaner.clean(text))
    push_parser(DocumentParser.new(self))
    body = open_element(:body)
    tokens.each { |tok| current_parser.grok(tok) }
    close_element(body)
  end

  def current_parser
    @parsers.last
  end

  def push_parser(parser)
    @parsers.push(parser)
  end

  def pop_parser
    @parsers.pop
  end

  def open_element(tag)
    e = Element.new(tag)
    @elements.last.add_child(e) unless @elements.empty?
    @elements.push(e).last
  end

  def close_element(element)
    unless element.equal?(@elements[-1])
      raise "Wrong element."
    end
    @elements.pop
  end

end

if __FILE__ == $0

  puts Markup.new.parse_text("abc\n\nefg")
  #puts Markup.new.parse_file('foo.txt')

  p = Element.new(:p, "normal text. ", Element.new(:i, "this is italic"), " more normal text.")

  puts "*** passing block ***"
  p.each { |c| puts c }

  x = p.each
  puts "*** got enumerator #{x} ***"
  x.each { |c| puts c }


  puts "*** for ***"
  for e in p
    puts e
  end

  puts "\n#{p.just_text}"

end
