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

  def initialize(markup, options={})
    @markup   = markup
    h = @@standard_options.merge(options)
    @options = {
      :block_elements => Set.new(h[:block_elements]),
      :divs           => Set.new(h[:divs]),
      :spans          => Set.new(h[:spans])
    }
  end

  def is_block?(tag)
    @options[:block_elements].include? tag
  end

  def is_div?(tag)
    @options[:divs].include?(tag)
  end

  def is_span?(tag)
    @options[:spans].include?(tag)
  end

  def open_tag(tag, attributes={})
    s = "#{(is_block? tag) ? "\n" : ""}<#{tag}"
    attributes.each { |k, v| s << " #{k}='#{v}'" }
    s << ">"
  end

  def close_tag(tag)
    "</#{tag}>#{(is_block? tag) ? "\n" : ""}"
  end

  def escaped_text(text)
    text.gsub(/&/, "&amp;").gsub(/</, "&lt;").gsub(/>/, "&gt;")
  end

  def walk(element, linkdefs, block)
    if element.is_a?(String)
      block.call escaped_text(element)
    else
      if element.tag == :link
        tag = :a
        attributes = { :href => linkdefs[element.link_key!] }
      elsif is_div? element.tag
        tag = :div
        attributes = { :class => element.tag }
      elsif is_span? element.tag
        tag = :span
        attributes = { :class => element.tag }
      else
        tag = element.tag
        attributes = {}
      end

      block.call open_tag tag, attributes
      element.children.each { |c| walk c, linkdefs, block }
      block.call close_tag tag
    end
  end

  # Emit the HTML to the block one bit of text at a time. Useful for
  # things like Sinatra and ERB.
  def each(&block)
    linkdefs = @markup.link_defs!
    walk @markup, linkdefs, block
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
