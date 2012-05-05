#!/usr/bin/env ruby -w
# encoding: UTF-8

libdir = File.dirname(__FILE__)
$LOAD_PATH.unshift(libdir) unless $LOAD_PATH.include?(libdir)

require 'markup'
require 'set'

class HTML

  @@standard_options = {
    # Tags that should be output as block elements. (With a newline
    # before the opening tag and after the losing tag.)
    :block_elements => [ :body,
                         :h1, :h2, :h3, :h4, :h5, :h6,
                         :p,
                         :blockquote,
                         :pre,
                         :ul, :ol, :li,
                         :dl, :dt, :dd
                       ],

    # List of tags that should be rewritten as <div class='#{name}'>
    :divs => [],

    # List of tags that should be rewritten as <span class='#{name}'>
    :spans => [],
  }

  class Yielder < Renderer

    def initialize(block, options)
      @block   = block
      @options = options
    end

    def is_div?(tag)
      @options[:divs].include?(tag)
    end

    def is_span?(tag)
      @options[:spans].include?(tag)
    end

    def open_element(tag)
      if is_div? tag
        @block.call("\n<div class='#{tag}'>")
      elsif is_span? tag
        @block.call("<span class='#{tag}'>")
      else
        @block.call("\n") if @options[:block_elements].include?(tag)
        @block.call("<#{tag}>")
      end
    end

    def close_element(tag)
      if is_div? tag
        @block.call('</div>\n');
      elsif is_span? tag
        @block.call('</span>');
      else
        @block.call("</#{tag}>")
        @block.call("\n") if @options[:block_elements].include?(tag)
      end
    end

    def render_text(text)
      @block.call(text.gsub(/&/, "&amp;").gsub(/</, "&lt;").gsub(/>/, "&gt;"))
    end
  end


  def initialize(markup, options={})
    @markup  = markup
    h = @@standard_options.merge(options)
    @options = {
      :block_elements => Set.new(h[:block_elements]),
      :divs           => Set.new(h[:divs]),
      :spans          => Set.new(h[:spans])
    }
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

  parser = Markup.new(:subdocs => [:note, :comment])

  ARGV.each do |file|
    markup = parser.parse_file(file)
    #HTML.new(markup).each { |s| print s }
    #HTML.new(markup).to_file('testout.html')
    print HTML.new(markup, :divs => [:intro], :spans => [:n])
  end

end
