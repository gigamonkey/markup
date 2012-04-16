#!/usr/bin/env ruby -w
# encoding: UTF-8

require './markup'

class Renderer

  @@standard_options = {
    :block_elements => [ :h1, :p, :blockquote, :pre ]
  }

  def initialize(options=nil)
    @options = options || @@standard_options
  end

  def escape(s)
    s = s.gsub(/&/, "&amp;")
    s = s.gsub(/</, "&lt;")
    s.gsub(/>/, "&gt;")
  end

  def render(markup)
    if markup.is_a?(String)
      print escape(markup)
    else
      tag, *children = markup
      open_tag(tag)
      children.each { |m| render(m) }
      close_tag(tag)
    end
  end

  def open_tag(tag)
    if @options[:block_elements].include?(tag)
      print "\n"
    end
    print "<#{tag}>"
  end

  def close_tag(tag)
    print "</#{tag}>"
    if @options[:block_elements].include?(tag)
      print "\n"
    end
  end



end

if __FILE__ == $0

  ARGV.each do |file|
    print Renderer.new.render(Markup.new(Set.new([:note, :comment])).parse_file(file).to_a)
  end

end
