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

#
# TextCleaner is responsible for converting tabs to spaces and
# removing trailing whitespace from lines.
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
    leading_spaces      = 0
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
          end
          yield t
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


if __FILE__ == $0

  #f = File.new(file, "r:UTF-8")
  #puts "initializing Parser for #{f} with encoding #{f.external_encoding}"
  e = TextCleaner.new.clean("abc   \t\n\txyz")
  #h = e.each.with_object(Hash.new(0)) { |c, h| h[c] += 1 }
  #puts "h: #{h}"
  x = e.each.with_object([]) { |c, s| s << c }
  puts x

end
