
#--
# Copyright (c) 2015-2015, John Mettraux, jmettraux@gmail.com
#
# Permission is hereby granted, free of charge, to any person obtaining a copy
# of this software and associated documentation files (the "Software"), to deal
# in the Software without restriction, including without limitation the rights
# to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
# copies of the Software, and to permit persons to whom the Software is
# furnished to do so, subject to the following conditions:
#
# The above copyright notice and this permission notice shall be included in
# all copies or substantial portions of the Software.
#
# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
# IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
# FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
# AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
# LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
# OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
# THE SOFTWARE.
#
# Made in Japan.
#++


module Raabro

  VERSION = '1.0.0'

  class Input

    attr_accessor :string, :offset
    attr_reader :options

    def initialize(string, offset=0, options={})

      @string = string
      @offset = offset
      @options = options
    end

    def match(str_or_regex)

      if str_or_regex.is_a?(Regexp)
        m = @string[@offset..-1].match(str_or_regex)
        m && (m.offset(0).first == 0) ? m[0].length : false
      else # String or whatever responds to #to_s
        s = str_or_regex.to_s
        l = s.length
        @string[@offset, l] == s ? l : false
      end
    end
  end

  class Tree

    attr_accessor :name, :input
    attr_accessor :result # ((-1 error,)) 0 nomatch, 1 success
    attr_accessor :offset, :length
    attr_accessor :parter, :children

    def initialize(name, parter, input)

      @result = 0
      @name = name
      @parter = parter
      @input = input
      @offset = input.offset
      @length = 0
      @children = []
    end

    def successful_children

      @children.select { |c| c.result == 1 }
    end

    def to_a(opts={})

      cn =
        opts[:leaves] && (@result == 1) && @children.empty? ?
        @input.string[@offset, @length] :
        @children.collect { |e| e.to_a(opts) }

      [ @name, @result, @offset, @length, @note, @parter, cn ]
    end
  end

  module ModuleMethods

    def match(name, input, parter, regex_or_string)

      r = Raabro::Tree.new(name, parter, input)

      if l = input.match(regex_or_string)
        r.result = 1
        r.length = l
        input.offset += l
      end

      r
    end

    def str(name, input, string)

      match(name, input, :str, string)
    end

    def rex(name, input, regex_or_string)

      match(name, input, :rex, Regexp.new(regex_or_string))
    end

    def quantify(parser)

      case parser
        when '?', :qmark then [ 0, 1 ]
        when '*', :star then [ 0, 0 ]
        when '+', :plus then [ 1, 0 ]
        else nil
      end
    end

    def narrow(parser)

      raise ArgumentError.new("lone quantifier #{parser}") if quantify(parser)

      return parser if parser.is_a?(Method)
      return method(parser) if parser.is_a?(Symbol)

      k, m = parser.to_s.split('.')
      k, m = [ Object, k ] unless m

      Kernel.const_get(k).method(m)
    end

    def parse(parser, input)

      narrow(parser).call(input)
    end

    def seq(name, input, *parsers)

      r = Tree.new(name, :seq, input)

      start = input.offset
      c = nil

      loop do

        pa = parsers.shift
        break unless pa

        if q = quantify(parsers.first)
          parsers.shift
          c = rep(nil, input, pa, *q)
          r.children.concat(c.children)
        else
          c = parse(pa, input)
          r.children << c
        end

        break if c.result != 1
      end

      if c && c.result == 1
        r.result = 1
        r.length = input.offset - start
      else
        input.offset = start
      end

      r
    end

    def alt(name, input, *parsers)

      greedy =
        if parsers.last == true || parsers.last == false
          parsers.pop
        else
          false
        end

      r = Tree.new(name, greedy ? :altg : :alt, input)

      start = input.offset
      c = nil

      parsers.each do |pa|

        cc = parse(pa, input)
        r.children << cc

        input.offset = start

        if greedy
          if cc.result == 1 && cc.length > (c ? c.length : -1)
            c.result = 0 if c
            c = cc
          end
        else
          c = cc
          break if c.result == 1
        end
      end

      if c && c.result == 1
        r.result = 1
        r.length = c.length
        input.offset = start + r.length
      end

      r
    end

    def altg(name, input, *parsers)

      alt(name, input, *parsers, true)
    end

    def rep(name, input, parser, min, max=0)

      min = 0 if min == nil || min < 0
      max = nil if max.nil? || max < 1

      r = Tree.new(name, :rep, input)
      start = input.offset
      count = 0

      loop do
        c = parse(parser, input)
        r.children << c
        break if c.result != 1
        count += 1
        break if max && count == max
      end

      if count >= min && (max == nil || count <= max)
        r.result = 1
        r.length = input.offset - start
      else
        input.offset = start
      end

      r
    end

    def ren(name, input, parser)

      r = parse(parser, input)
      r.name = name

      r
    end
    #class << self; alias rename ren; end
    alias rename ren

    def all(name, input, parser)

      start = input.offset
      length = input.string.length - input.offset

      r = Tree.new(name, :all, input)
      c = parse(parser, input)
      r.children << c

      if c.length < length
        input.offset = start
      else
        r.result = 1
        r.length = c.length
      end

      r
    end

    def eseq(name, input, startpa, eltpa, seppa=nil, endpa=nil)

      jseq = false

      if seppa.nil? && endpa.nil?
        jseq = true
        seppa = eltpa; eltpa = startpa; startpa = nil
      end

      start = input.offset
      r = Tree.new(name, jseq ? :jseq : :eseq, input)
      r.result = 1
      c = nil

      if startpa
        c = parse(startpa, input)
        r.children << c
        r.result = 0 if c.result != 1
      end

      if r.result == 1

        i = 1
        count = 0

        loop do

          i = (i + 1) % 2
          pa = i == 0 ? eltpa : seppa

          c = parse(pa, input)
          r.children << c

          break if c.result != 1

          count += 1
        end

        r.result = 0 if jseq && count < 1
      end

      if r.result == 1 && endpa
        c = parse(endpa, input)
        r.children << c
        r.result = 0 if c.result != 1
      end

      if r.result == 1
        r.length = input.offset - start
      else
        input.offset = start
      end

      r
    end
    alias jseq eseq
  end
  extend ModuleMethods

  def self.included(target)

    target.instance_eval { extend ::Raabro::ModuleMethods }
  end
end

