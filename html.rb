#!/usr/bin/env ruby -w
# encoding: UTF-8

libdir = File.dirname(__FILE__)
$LOAD_PATH.unshift(libdir) unless $LOAD_PATH.include?(libdir)

require 'markup'

class HTML

  @@standard_options = {
    :block_elements => [ :body,
                         :h1, :h2, :h3, :h4, :h5, :h6,
                         :p,
                         :blockquote,
                         :pre,
                         :ul, :ol, :li,
                         :dl, :dt, :dd
                       ]
  }

  class Yielder < Renderer

    def initialize(block, options)
      @block   = block
      @options = options
    end

    def open_element(tag)
      @block.call("\n") if @options[:block_elements].include?(tag)
      @block.call("<#{tag}>")
    end

    def close_element(tag)
      @block.call("</#{tag}>")
      @block.call("\n") if @options[:block_elements].include?(tag)
    end

    def render_text(text)
      @block.call(text.gsub(/&/, "&amp;").gsub(/</, "&lt;").gsub(/>/, "&gt;"))
    end
  end


  def initialize(markup, options=nil)
    @markup  = markup
    @options = options || @@standard_options
  end

  # Emit the HTML to the block one bit of text at a time. Useful for
  # things like Sinatra and ERB.
  def each(&block)
    @markup.render(Yielder.new(block, @options))
  end

  # Output HTML to the named file.
  def to_file(file)
    File.open(file, 'w') do |f|
      each { |text| f.print text }
    end
  end

  # Return the HTML as a string.
  def to_s()
    s = ''
    each { |text| s << text }
    s
  end
end


if __FILE__ == $0

  parser = Markup.new(Set.new([:note, :comment]))

  ARGV.each do |file|
    markup = parser.parse_file(file)
    #HTML.new(markup).each { |s| print s }
    #HTML.new(markup).to_file('testout.html')
    print HTML.new(markup)
  end

end
