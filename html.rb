#!/usr/bin/env ruby -w
# encoding: UTF-8

require './markup'

class Renderer

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
      print "<#{tag}>"
      children.each { |m| render(m) }
      print "</#{tag}>"
    end
  end
end

if __FILE__ == $0

  ARGV.each do |file|
    print Renderer.new.render(Markup.new(Set.new([:note, :comment])).parse_file(file).to_a)
  end

end
