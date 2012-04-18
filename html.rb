#!/usr/bin/env ruby -w
# encoding: UTF-8

require './markup'

class HTML < Renderer

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

  def initialize(options=nil)
    @options = options || @@standard_options
  end

  def open_element(tag)
    print "\n" if @options[:block_elements].include?(tag)
    print "<#{tag}>"
  end

  def close_element(tag)
    print "</#{tag}>"
    print "\n" if @options[:block_elements].include?(tag)
  end

  def render_text(text)
    print text.gsub(/&/, "&amp;").gsub(/</, "&lt;").gsub(/>/, "&gt;")
  end
end

if __FILE__ == $0

  ARGV.each do |file|
    Markup.new(Set.new([:note, :comment])).parse_file(file).render(HTML.new)
  end

end
