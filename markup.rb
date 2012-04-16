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
require 'set'

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

  attr_reader :children
  attr_accessor :tag

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

    newlines         = 0
    newline_position = nil
    leading_spaces   = 0
    previous_token   = nil
    in_verbatim      = false

    if block_given?
      input_tokens.each do |t|
        if t == "\n"
          if newlines == 0 then newline_position = [t.line, t.column] end
          newlines += 1
        else
          if newlines > 0
            if newlines == 1
              yield Token.new(:newline, *newline_position, self)
            else
              (newlines - 1).times { yield Token.new(:blank, *newline_position, self) }
            end
            newlines = 0
            leading_spaces = 0
          end

          if leading_spaces # Note that 0 is a true value.
            if t == " "
              leading_spaces += 1
            else

              # First close any open indented sections.
              if leading_spaces < @current_indentation
                if in_verbatim
                  yield Token.new(:close_verbatim, t.line, 0, self)
                  in_verbatim = false
                  @current_indentation -= 3
                end

                while leading_spaces < @current_indentation
                  yield Token.new(:close_blockquote, t.line, 0, self)
                    @current_indentation -= 2
                end
              end

              if leading_spaces > @current_indentation
                spaces = leading_spaces - @current_indentation
                if in_verbatim
                  spaces.times { yield Token.new(" ", t.line, 0, self) }
                else
                  if spaces == 1 # -2 + 3 = 1
                    yield Token.new(:close_blockquote, t.line, 0, self)
                    yield Token.new(:open_verbatim, t.line, 0, self)
                    @current_indentation += 1
                    in_verbatim = true;

                  elsif spaces == 2
                    yield Token.new(:open_blockquote, t.line, 0, self)
                    @current_indentation += 2

                  elsif spaces >= 3
                    yield Token.new(:open_verbatim, t.line, 0, self)
                    (spaces - 3).times { yield Token.new(" ", t.line, 0, self) }
                    @current_indentation += 3
                    in_verbatim = true
                  end
                end
              end

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
          if in_verbatim
            yield Token.new(:close_verbatim, previous_token.line, previous_token.column, self)
            in_verbatim = false
            @current_indentation -= 3
          end

          while @current_indentation > 0
            yield Token.new(:close_blockquote, previous_token.line, 0, self)
            @current_indentation -= 2
          end
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
  def initialize(markup, brace_is_eof=false)
    @markup       = markup
    @brace_is_eof = brace_is_eof
  end
end

class DocumentParser < Parser

  def initialize(markup, subdoc=false, section=false)
    super(markup, subdoc)
    @subdoc = subdoc
    @section = section
  end

  def grok(token)
    case token.value
    when :blank, :newline
      #raise "Parse error #{token}"
    when "*"
      @markup.push_parser(HeaderParser.new(@markup))
    when '-'
      @markup.push_parser(PossibleModelineParser.new(@markup, token))
    when :open_blockquote
      @markup.push_parser(BlockquoteOrListParser.new(@markup, @brace_is_eof))
    when :open_verbatim
      v = @markup.open_element(:pre)
      @markup.push_parser(VerbatimParser.new(@markup, v))
    when '['
      @markup.push_parser(AmbiguousLinkParser.new(@markup))
      @markup.push_parser(LinkParser.new(@markup))
    when '}'
      if @brace_is_eof
        @markup.close_element(@subdoc, token)
        @markup.pop_parser
      end
    when '§'
      s = @markup.open_element(:section)
      @markup.push_parser(ParagraphParser.new(@markup, s, @brace_is_eof))
      @markup.current_parser.grok(token)
    when '#'
      if not @section
        # This is the top level document parser so this may be the
        # beginning of a section.
        @markup.push_parser(SectionStartParser.new(@markup, token))
      else
        # This is a nested section parser so this may be the end of
        # the section.
        @markup.push_parser(SectionEndParser.new(@markup, token, @subdoc))
      end

    else
      p = @markup.open_element(:p)
      @markup.push_parser(ParagraphParser.new(@markup, p, @brace_is_eof))
      @markup.current_parser.grok(token)
    end
  end
end

class PossibleModelineParser < Parser

  def initialize(markup, token)
    super(markup)
    @tokens = [ token ]
    @in_modeline = false
  end

  def grok(token)
    if @tokens.length == 1 and token.value == '*'
      @tokens << token
    elsif @tokens.length == 2 and token.value == '-'
      @in_modeline = true
    elsif @in_modeline
      if token.value == :blank
        @markup.pop_parser
      end
    else
      @markup.pop_parser
      p = @markup.open_element(:p)
      @markup.push_parser(ParagraphParser.new(@markup, p))
      @tokens.each { |tok| @markup.current_parser.grok(tok) }
      @markup.current_parser.grok(token)
    end
  end
end

class SectionStartParser < Parser

  def initialize(markup, token)
    super(markup)
    @tokens = [ token ]
  end

  def grok(token)
    if @tokens.length == 1 and token.value == '#'
      @tokens << token
    elsif @tokens.length == 2 and token.value == ' '
      @markup.pop_parser
      @markup.push_parser(SectionNameParser.new(@markup))
    else
      raise "Parser error: #{token}"
    end
  end
end

class SectionEndParser < Parser

  def initialize(markup, token, section)
    super(markup)
    @tokens  = [ token ]
    @section = section
  end

  def grok(token)
    if @tokens.length == 1 and token.value == '#'
      @tokens << token
    elsif @tokens.length == 2 and token.value == '.'
      @tokens << token
    elsif @tokens.length == 3 and token.value == :blank
      @markup.pop_parser # this one
      @markup.pop_parser # document parser
      @markup.close_element(@section)
    else
      raise "Parser error: #{token}"
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
      tag = @name.to_sym
      e = @markup.open_element(tag)
      if @markup.subdocs.include?(tag)
        @markup.push_parser(DocumentParser.new(@markup, e))
      else
        @markup.push_parser(BraceDelimetedParser.new(@markup, e))
      end
    else
      # FIXME: should check that we only get legal name characters.
      @name << token.value
    end
  end
end

class SectionNameParser < Parser

  def initialize(markup)
    super(markup)
    @name = ''
  end

  def grok(token)
    case token.value
    when :blank
      @markup.pop_parser
      tag = @name.to_sym
      e = @markup.open_element(tag)
      @markup.push_parser(DocumentParser.new(@markup, e, true))
    else
      # FIXME: should check that we only get legal name characters.
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
    when '['
      @markup.push_parser(LinkParser.new(@markup))
    else
      @element.add_text(token.value)
    end
  end
end

class SlashParser < Parser

  def grok(token)
    case token.value
    when '\\', '{', '}', '*', '-', '#', '[', '<', '|'
      @markup.pop_parser
      @markup.current_element.add_text(token.value)
    else
      @markup.pop_parser
      @markup.push_parser(NameParser.new(@markup))
      @markup.current_parser.grok(token)
    end
  end
end

class LinkParser < Parser

  def initialize(markup)
    super(markup)
    @link = @markup.open_element(:link)
    @key = false
  end

  def grok(token)
    case token.value
    when '|'
      @key = @markup.open_element(:key)
    when ']'
      @markup.pop_parser
      if @key
        @markup.close_element(@key, token)
      end
      @markup.close_element(@link, token)
    when '\\'
      @markup.push_parser(SlashParser.new(@markup))
    when :newline
      if @key
        @key.add_text(' ')
      else
        @link.add_text(' ')
      end
    else
      if @key
        @key.add_text(token.value)
      else
        @link.add_text(token.value)
      end
    end
  end
end


class AmbiguousLinkParser < Parser

  def initialize(markup)
    super(markup)
    @element = @markup.open_element(nil)
    @tokens = []
  end

  def grok(token)
    if @tokens.length == 0 and token.value == ' '
      @tokens << token
    elsif @tokens.length == 1 and token.value == '<'
      @element.tag = :link_def
      @markup.pop_parser # ourself
      @markup.push_parser(LinkdefParser.new(@markup, false))
      @markup.current_parser.grok(token)
    else
      @element.tag = :p
      @markup.pop_parser
      @markup.push_parser(ParagraphParser.new(@markup, @element))
      @tokens << token
      @tokens.each { |tok| @markup.current_parser.grok(tok) }
    end
  end
end



class LinkdefParser < Parser

  def initialize(markup, open_element=true)
    super(markup)
    if open_element
      @linkdef = @markup.open_element(:link_def)
    else
      @linkdef = @markup.current_element
    end
  end

  def grok(token)
    case token.value
    when ' '
    when '<'
      @markup.push_parser(UrlParser.new(@markup))
    when :blank
      @markup.pop_parser
      @markup.close_element(@linkdef)
    end
  end
end

class UrlParser < Parser

  def initialize(markup)
    super(markup)
    @url = @markup.open_element(:url)
  end

  def grok(token)
    case token.value
    when '>'
      @markup.pop_parser
      @markup.close_element(@url)
    else
      @url.add_text(token.value)
    end
  end
end

class ParagraphParser < Parser

  def initialize(markup, p, brace_is_eof=false)
    super(markup, brace_is_eof)
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
    when '['
      @markup.push_parser(LinkParser.new(@markup))
    when '}'
      if @brace_is_eof
        @markup.close_element(@p, token)
        @markup.pop_parser
        @markup.current_parser.grok(token)
      end
    else
      @p.add_text(token.value)
    end
  end
end

class HeaderParser < Parser

  def initialize(markup, brace_is_eof=false)
    super(markup, brace_is_eof)
    @stars = 1
  end

  def grok(token)
    case token.value
    when "*"
      @stars += 1
    when " "
      h = @markup.open_element("h#{@stars}".to_sym)
      @markup.pop_parser
      @markup.push_parser(ParagraphParser.new(@markup, h, @brace_is_eof))
    else
      raise "Bad token: #{token}"
    end
  end
end

class BlockquoteOrListParser < Parser

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
    case token.value
    when :blank, :newline
      raise "Parse error #{token}"
    when "*"
      @markup.push_parser(HeaderParser.new(@markup))
    when :open_blockquote
      @markup.push_parser(BlockquoteOrListParser.new(@markup, @brace_is_eof))
    when :open_verbatim
      v = @markup.open_element(:pre)
      @markup.push_parser(VerbatimParser.new(@markup, v))
    when :close_blockquote
      @markup.close_element(@element, token)
      @markup.pop_parser
    else
      p = @markup.open_element(:p)
      @markup.push_parser(ParagraphParser.new(@markup, p))
      @markup.current_parser.grok(token)
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

    case token.value
    when @marker
      @markup.push_parser(space_eater(token))
    when :close_blockquote
      @markup.close_element(@list, token)
      @markup.pop_parser
    else
      raise "Parse error: expected #{@marker} or :close_blockquote got #{token}"
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

  def initialize(markup, verbatim)
    super(markup)
    @verbatim = verbatim
    @blanks   = 0
  end

  def grok(token)
    case token.value
    when :blank
      @blanks += 1
    when :newline
      @verbatim.add_text("\n")
    when :close_verbatim
      @markup.close_element(@verbatim, token)
      @markup.pop_parser
    else
      if @blanks > 0
        (@blanks + 1).times { @verbatim.add_text("\n") }
        @blanks = 0
      end
      @verbatim.add_text(token.value)
    end
  end
end

class Markup

  attr_reader :subdocs

  def initialize(subdocs=Set.new, tabwidth=8)
    @subdocs   = subdocs
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

  def dump_parse_state(token)
    puts "At token: #{token}"
    puts "elements: #{@elements}"
    puts "parsers: #{@parsers}"
  end

end

if __FILE__ == $0

  ARGV.each do |file|
    puts "\n\nFile: #{file}:::\n"
    print JSON.dump(Markup.new(Set.new([:note])).parse_file(file).to_a)
    #File.open(file) { |f| puts Markup.new.tokenize(f).to_a }
  end

end
