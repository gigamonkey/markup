#!/usr/bin/env ruby -w
# encoding: UTF-8

#
# A Token represents a character or a slightly abstracted element of a
# text (e.g. :newline, :blankline, etc.) along with its starting
# position in the original text. A Token can be compared for equality
# with a plain character as long as the token is on the left-hand
# side.
#

require 'json'

class Token

  attr_reader :line, :column, :value
  attr_accessor :tokenizer

  def initialize(value, line, column, tokenizer=nil)
    @value     = value
    @line      = line
    @column    = column
    @tokenizer = tokenizer
  end

  def text
    @value.to_s
  end

  def to_s
    "#<Token: '#{@value}'; line: #{@line}; column: #{@column}>"
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
            whitespace.chars do |w|
              if w == " "
                yield Token.new(w, line, column)
              elsif w == "\t"
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

  def initialize
    @current_indentation = 0
  end

  def tokens(input_tokens)

    newlines            = 0
    newline_position    = nil
    leading_spaces      = 0
    previous_token      = nil

    if block_given?
      input_tokens.each do |t|
        if t == "\n"
          if newlines == 0 then newline_position = [t.line, t.column] end
          newlines += 1
        else
          if newlines > 0
            yield Token.new(newlines == 1 ? :newline : :blank, *newline_position, self)
            newlines = 0
            leading_spaces = 0
          end

          if leading_spaces
            if t == " "
              leading_spaces += 1
            else
              if leading_spaces > @current_indentation
                yield Token.new([:indent, leading_spaces - @current_indentation], t.line, 0, self)
              elsif @current_indentation > leading_spaces
                yield Token.new([:outdent, @current_indentation - leading_spaces], t.line, 0, self)
              end
              @current_indentation = leading_spaces
              leading_spaces = false
              t.tokenizer = self
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
        yield Token.new(:blank, previous_token.line, previous_token.column, self)

        if @current_indentation > 0
          yield Token.new([:outdent, @current_indentation], previous_token.line, previous_token.column, self)
        end
      end

    else
      Enumerator.new(self, :tokens, input_tokens)
    end
  end

  def add_indentation(n)
    @current_indentation += n
  end

end

class Parser
  def initialize(markup)
    @markup = markup
  end

  def expand_outdentation(outdentation, token, element, amount=2)
    if outdentation >= amount
      @markup.close_element(element, token)
      @markup.pop_parser
    end
    # Pass along any extra outdentation.
    if outdentation > amount
      new_outdent = Token.new([:outdent, outdentation - amount], token.line, 0, token.tokenizer)
      @markup.current_parser.grok(new_outdent)
    end
  end

end

class DocumentParser < Parser

  def grok(token)
    what, extra = token.value

    case what
    when :blank, :newline
      raise "Parse error #{token}"
    when "*"
      @markup.push_parser(HeaderParser.new(@markup))
    when :indent
      indentation = extra
      case
      when indentation == 2
        @markup.push_parser(BlockquoteOrListParser.new(@markup))
      when indentation >= 3
        v = @markup.open_element(:pre)
        @markup.push_parser(VerbatimParser.new(@markup, v, indentation - 3))
      end
    else
      p = @markup.open_element(:p)
      @markup.push_parser(ParagraphParser.new(@markup, p))
      @markup.current_parser.grok(token)
    end
  end
end

class NameParser < Parser

  def initialize(markup)
    super(markup)
    @name = ''
  end

  def grok(token)
    case token.value
    when '{'
      @markup.pop_parser
      e = @markup.open_element(@name.to_sym)
      @markup.push_parser(BraceDelimetedParser.new(@markup, e))
    else
      @name << token.value
    end
  end
end

class BraceDelimetedParser < Parser

  def initialize(markup, element)
    super(markup)
    @element = element
  end

  def grok(token)
    case token.value
    when '}'
      @markup.close_element(@element)
      @markup.pop_parser
    when '\\'
      @markup.push_parser(SlashParser.new(@markup))
    else
      @element.add_text(token.value)
    end
  end
end


class SlashParser < Parser

  def grok(token)
    case token.value
    when '\\', '{', '}', '*', '-', '#'
      @markup.pop_parser
      @markup.current_element.add_text(token.value)
    else
      @markup.pop_parser
      @markup.push_parser(NameParser.new(@markup))
      @markup.current_parser.grok(token)
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
      @markup.close_element(@p, token)
      @markup.pop_parser
    when :newline
      @p.add_text(' ')
    when '\\'
      @markup.push_parser(SlashParser.new(@markup))
    else
      # FIXME: this could be tagged text
      @p.add_text(token.value)
    end
  end
end

class HeaderParser < Parser

  def initialize(markup)
    super(markup)
    @stars = 1
  end

  def grok(token)
    case token.value
    when "*"
      @stars += 1
    when " "
      h = @markup.open_element("h#{@stars}".to_sym)
      @markup.pop_parser
      @markup.push_parser(ParagraphParser.new(@markup, h))
    else
      raise "Bad token: #{token}"
    end
  end
end

class BlockquoteOrListParser < Parser

  def initialize(markup)
    super(markup)
  end

  def grok(token)
    tag, parserClass =
      case token.value
      when '#'
        [:ol, ListParser]
      when '-'
        [:ul, ListParser]
      else
        [:blockquote, IndentedElementParser]
      end

    element = @markup.open_element(tag)
    parser  = parserClass.new(@markup, element)
    @markup.pop_parser
    @markup.push_parser(parser)
    parser.grok(token)
  end
end

class IndentedElementParser < Parser

  def initialize(markup, element)
    super(markup)
    @element = element
  end

  def grok(token)
    what, extra = token.value

    case what
    when :blank, :newline
      raise "Parse error #{token}"
    when "*"
      @markup.push_parser(HeaderParser.new(@markup))
    when :indent
      indentation = extra
      case
      when indentation == 2
        @markup.push_parser(BlockquoteOrListParser.new(@markup))
      when indentation >= 3
        v = @markup.open_element(:pre)
        @markup.push_parser(VerbatimParser.new(@markup, v, indentation - 3))
      end
    when :outdent
      expand_outdentation(extra, token, @element)
    else
      # FIXME: this could be tagged text
      p = @markup.open_element(:p)
      p.add_text(token.value)
      @markup.push_parser(ParagraphParser.new(@markup, p))
    end
  end
end

class ListParser < Parser

  def initialize(markup, list)
    super(markup)
    @list   = list
    @marker = nil
  end

  def space_eater(token)
    TokenEater.new(@markup, ' ') do
      @markup.pop_parser
      token.tokenizer.add_indentation(2)
      item = @markup.open_element(:li)
      @markup.push_parser(IndentedElementParser.new(@markup, item))
    end
  end

  def grok(token)
    # The first token we see is our list marker (either '#' or '-').
    if @marker.nil? then @marker = token.value end

    what, extra = token.value

    case what
    when @marker
      @markup.push_parser(space_eater(token))
    when :outdent
      expand_outdentation(extra, token, @list)
    else
      raise "Parse error: expected #{@marker} or :outdent got #{token}"
    end
  end
end

class TokenEater < Parser

  def initialize(markup, value, &block)
    super(markup)
    @value = value
    @block = block
  end

  def grok(token)
    case token.value
    when @value
      @block.call
    else
      raise "Parse error expected <#{@value}> got #{token.value}"
    end
  end
end

class VerbatimParser < Parser

  def initialize(markup, verbatim, initial_indentation=0)
    super(markup)
    @verbatim          = verbatim
    @extra_indentation = initial_indentation
    @blanks            = 0
    @beginning_of_line = true
  end

  def grok(token)
    what, extra = token.value

    case what
    when :blank
      @blanks += 1
    when :newline
      @verbatim.add_text("\n")
    when :indent
      @extra_indentation += extra
      @beginning_of_line = true
    when :outdent
      if extra > @extra_indentation
        expand_outdentation(extra - @extra_indentation, token, @verbatim, 3)
      else
        @extra_indentation -= extra
        @beginning_of_line = true
      end
    else
      @blanks.times { @verbatim.add_text("\n\n") }
      @blanks = 0
      if @beginning_of_line
        @extra_indentation.times { @verbatim.add_text(" ") }
        @beginning_of_line = false
      end
      @verbatim.add_text(token.value)
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
    push_parser(DocumentParser.new(self))
    body = open_element(:body)
    tokenize(text).each { |tok| current_parser.grok(tok) }
    close_element(body)
  end

  def tokenize(text)
    @tokenizer.tokens(@cleaner.clean(text))
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

  def close_element(element, token=nil)
    unless element.equal?(@elements[-1])
      raise "Trying to close element #{element}, found #{@elements} at #{token}"
    end
    @elements.pop
  end

  def current_element
    @elements.last
  end

end

if __FILE__ == $0

  ARGV.each do |file|
    puts "\n\nFile: #{file}:::\n"
    print JSON.dump(Markup.new.parse_file(file).to_a)
    #File.open(file) { |f| puts Markup.new.tokenize(f).to_a }
  end

end
