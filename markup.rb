#!/usr/bin/env ruby -w
# encoding: UTF-8

#
# TextCleaner is responsible for converting tabs to spaces and
# removing trailing whitespace from lines.
#
class TextCleaner

  def initialize(tabwidth=8)
    @tabspaces = " " * tabwidth
  end

  def clean(text)
    if block_given?

      whitespace = ''
      afterCR      = false

      text.chars.each do |c|

        # The previous char was a bare CR so convert to a LF
        if afterCR and c != "\n"
          whitespace = ''
          yield "\n"
        end

        afterCR = false

        if c == "\t"
          whitespace += @tabspaces
        elsif c == " "
          whitespace += c
        elsif c == "\n"
          whitespace = ''
          yield c
        elsif c == "\r"
          afterCR = true
        else
          whitespace.chars { |c| yield c }
          whitespace = ''
          yield c
        end
      end

      # Last character was a bare CR
      if afterCR then yield "\n" end
    else
      Enumerator.new(self, :clean, text)
    end
  end
end

if __FILE__ == $0

  #f = File.new(file, "r:UTF-8")
  #puts "initializing Parser for #{f} with encoding #{f.external_encoding}"
  e = TextCleaner.new("abc   \t\n\txyz").each
  #h = e.each.with_object(Hash.new(0)) { |c, h| h[c] += 1 }
  #puts "h: #{h}"
  x = e.each.with_object('') { |c, s| s << c }
  puts x

end
