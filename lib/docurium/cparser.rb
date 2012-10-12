class Docurium
  class CParser

    # Remove common prefix of all lines in comment.
    # Otherwise tries to preserve formatting in case it is relevant.
    def cleanup_comment(comment)
      return "" unless comment

      lines = 0
      prefixed = 0
      shortest = nil

      compacted = comment.sub(/^\n+/,"").sub(/\n\s*$/, "\n")

      compacted.split(/\n/).each do |line|
        lines += 1
        if line =~ /^\s*\*\s*$/ || line =~ /^\s*$/
          # don't count length of blank lines or lines with just a " * " on
          # them towards shortest common prefix
          prefixed += 1
          shortest = line if shortest.nil?
        elsif line =~ /^(\s*\*\s*)/
          prefixed += 1
          shortest = $1 if shortest.nil? || shortest.length > $1.length
        end
      end

      if shortest =~ /\s$/
        shortest = Regexp.quote(shortest.chop) + "[ \t]"
      elsif shortest
        shortest = Regexp.quote(shortest)
      end

      if lines == prefixed && !shortest.nil? && shortest.length > 0
        if shortest =~ /\*/
          return comment.gsub(/^#{shortest}/, "").gsub(/^\s*\*\s*\n/, "\n")
        else
          return comment.gsub(/^#{shortest}/, "")
        end
      else
        return comment
      end
    end

    # Find the shortest common prefix of an array of strings
    def shortest_common_prefix(arr)
      arr.inject do |pfx,str|
        pfx = pfx.chop while pfx != str[0...pfx.length]; pfx
      end
    end

    # Match #define A(B) or #define A
    # and convert a series of simple #defines into an enum
    def detect_define(d)
      if d[:body] =~ /\A\#\s*define\s+((\w+)\([^\)]+\))/
        d[:type] = :macro
        d[:decl] = $1.strip
        d[:name] = $2
        d[:tdef] = nil
      elsif d[:body] =~ /\A\#\s*define\s+(\w+)/
        names = []
        d[:body].scan(/\#\s*define\s+(\w+)/) { |m| names << m[0].to_s }
        d[:tdef] = nil
        names.uniq!
        if names.length == 1
          d[:type] = :define
          d[:decl] = names[0]
          d[:name] = names[0]
        elsif names.length > 1
          d[:type] = :enum
          d[:decl] = names
          d[:name] = shortest_common_prefix(names)
          d[:name].sub!(/_*$/, '')
        end
      end
    end

    # Take a multi-line #define and join into a simple definition
    def join_define(text)
      text = text.split("\n\n", 2).first || ""

      # Ruby 1.8 does not support negative lookbehind regex so let's
      # get the joined macro definition a slightly more awkward way
      text.split(/\s*\n\s*/).inject("\\") do |val, line|
        (val[-1] == ?\\) ? val = val.chop.strip + " " + line : val
      end.strip.gsub(/^\s*\\*\s*/, '')
    end

    # Process #define A(B) macros
    def parse_macro(d)
      if d[:body] =~ /define\s+#{Regexp.quote(d[:name])}\([^\)]*\)[ \t]*(.*)/m
        d[:value] = join_define($1)
      end
      d[:comments] = d[:rawComments].strip
    end

    # Process #define A ... macros
    def parse_define(d)
      if d[:body] =~ /define\s+#{Regexp.quote(d[:name])}[ \t]*(.*)/
        d[:value] = join_define($1)
      end
      d[:comments] = d[:rawComments].strip
    end

    # Match enum {} (and possibly a typedef thereof)
    def detect_enum(d)
      if d[:body] =~ /\A(typedef)?\s*enum\s*\{([^\}]+)\}\s*([^;]+)?;/i
        typedef, values, name = $1, $2, $3
        d[:type] = :enum
        d[:decl] = values.strip.split(/\s*,\s*/).map do |v|
          v.split(/\s*=\s*/)[0].strip
        end
        if typedef.nil?
          d[:name] = shortest_common_prefix(d[:decl])
          d[:name].sub!(/_*$/, '')
          # Using the common prefix for grouping enum values is a little
          # overly aggressive in some cases.  If we ended up with too short
          # a prefix or a prefix which is too generic, then skip it.
          d[:name] = nil unless d[:name].scan('_').length > 1
        else
          d[:name] = name
        end
        d[:tdef] = typedef
      end
    end

    # Process enum definitions
    def parse_enum(d)
      if d[:decl].respond_to? :map
        d[:block] = d[:decl].map { |v| v.strip }.join("\n")
      else
        d[:block] = d[:decl]
      end
      d[:comments] = d[:rawComments].strip
    end

    # Match struct {} (and typedef thereof) or opaque struct typedef
    def detect_struct(d)
      if d[:body] =~ /\A(typedef)?\s*struct\s*(\w+)?\s*\{([^\}]+)\}\s*([^;]+)?/i
        typedef, name1, fields, name2 = $1, $2, $3, $4
        d[:type] = :struct
        d[:name] = typedef.nil? ? name1 : name2;
        d[:tdef] = typedef
        d[:decl] = fields.strip.split(/\s*\;\s*/).map do |x|
          x.strip.gsub(/\s+/, " ").gsub(/\(\s+/,"(")
        end
      elsif d[:body] =~ /\A(typedef)\s+struct\s+\w+\s+(\w+)/
        d[:type] = :struct
        d[:decl] = ""
        d[:name] = $2
        d[:tdef] = $1
      end
    end

    # Process struct definition
    def parse_struct(d)
      if d[:decl].respond_to? :map
        d[:block] = d[:decl].map { |v| v.strip }.join("\n")
      else
        d[:block] = d[:decl]
      end
      d[:comments] = d[:rawComments].strip
    end

    # Match other typedefs, checking explicitly for function pointers
    # but otherwise just trying to extract a name as simply as possible.
    def detect_typedef(d)
      if d[:body] =~ /\Atypedef\s+([^;]+);/
        d[:decl] = $1.strip
        if d[:decl] =~ /\S+\s+\(\*([^\)]+)\)\(/
          d[:type] = :fnptr
          d[:name] = $1
        else
          d[:type] = :typedef
          d[:name] = d[:decl].split(/\s+/).last
        end
      end
    end

    # Process typedef definition
    def parse_typedef(d)
      d[:comments] = d[:rawComments].strip
    end

    # Process function pointer typedef definition
    def parse_fnptr(d)
      d[:comments] = d[:rawComments].strip
    end

    # Match function prototypes or inline function declarations
    def detect_function(d)
      if d[:body] =~ /[;\{]/
        d[:type] = :file
        d[:decl] = ""

        proto = d[:body].split(/[;\{]/, 2).first.strip
        if proto[-1] == ?)
          (proto.length - 1).downto(0) do |p|
            tail = proto[p .. -1]
            if tail.count(")") == tail.count("(")
              if proto[0..p] =~ /(\w+)\(\z/
                d[:name] = $1
                d[:type] = :function
                d[:decl] = proto
              end
              break
            end
          end
        end
      end
    end

    # Process function prototype and comments
    def parse_function(d)
      d[:args] = []

      rval, argline = d[:decl].split(/\s*#{Regexp.quote(d[:name])}\s*/, 2)

      # clean up rval if it is like "extern static int" or "GIT_EXTERN(int)"
      while rval =~ /[A-Za-z0-9_]+\(([^\)]+)\)$/i
        rval = $1
      end
      rval.gsub!(/extern|static/, '')
      rval.strip!
      d[:return] = { :type => rval }

      # clean up argline
      argline = argline.slice(1..-2) while argline[0] == ?( && argline[-1] == ?)
      d[:argline] = argline.strip
      d[:args] = []
      left = 0

      # parse argline
      (0 .. argline.length).each do |i|
        next unless argline[i] == ?, || argline.length == i

        s = argline.slice(left .. i)
        next unless s.count("(") == s.count(")")

        s.chop! if argline[i] == ?,
        s.strip!

        if s =~ /\(\s*\*\s*(\w+)\s*\)\s*\(/
          argname = $1
          d[:args] << {
            :name => argname,
            :type => s.sub(/\s*#{Regexp.quote(argname)}\s*/, '').strip
          }
        elsif s =~ /\W(\w+)$/
          argname = $1
          d[:args] << {
            :name => argname,
            :type => s[0 ... - argname.length].strip,
          }
        else
          # argline is probably something like "(void)"
        end

        left = i + 1
      end

      # parse comments
      if d[:rawComments] =~ /\@(param|return)/i
        d[:args].each do |arg|
          param_comment = /\@param\s+#{Regexp.quote(arg[:name])}/.match(d[:rawComments])
          if param_comment
            after = param_comment.post_match
            end_comment = after.index(/(?:@param|@return|\Z)/)
            arg[:comment] = after[0 ... end_comment].strip.gsub(/\s+/, ' ')
          end
        end

        return_comment = /\@return\s+/.match(d[:rawComments])
        if return_comment
          after = return_comment.post_match
          d[:return][:comment] = after[0 ... after.index(/(?:@param|\Z)/)].strip.gsub(/\s+/, ' ')
        end
      else
        # support for TomDoc params
      end

      # add in inline parameter comments
      if d[:inlines] # array of [param line]/[comment] pairs
        d[:inlines].each do |inl|
          d[:args].find do |arg|
            if inl[0] =~ /\b#{Regexp.quote(arg[:name])}$/
              arg[:comment] += "\n#{inl[1]}"
            end
          end
        end
      end

      # generate function signature
      d[:sig] = d[:args].map { |a| a[:type].to_s }.join('::')

      # pull off function description
      if d[:rawComments] =~ /^\s*(public|internal|deprecated):/i
        # support for TomDoc description
      else
        desc, comments = d[:rawComments].split("\n\n", 2)
        d[:description] = desc.strip
        d[:comments] = comments || ""
        params_start = d[:comments].index(/\s?\@(?:param|return)/)
        d[:comments] = d[:comments].slice(0, params_start) if params_start
      end
    end

    # Match otherwise unrecognized commented blocks
    def detect_catchall(d)
      d[:type] = :file
      d[:decl] = ""
    end

    # Process comment blocks that are only associated with the whole file.
    def parse_file(d)
      m = []
      d[:brief]    = m[1] if m = /@brief (.*?)$/.match(d[:rawComments])
      d[:defgroup] = m[1] if m = /@defgroup (.*?)$/.match(d[:rawComments])
      d[:ingroup]  = m[1] if m = /@ingroup (.*?)$/.match(d[:rawComments])
      comments = d[:rawComments].gsub(/^@.*$/, '').strip + "\n"
      if d[:comments]
        d[:comments] = d[:comments].strip + "\n\n" + comments
      else
        d[:comments] = comments
      end
    end

    # Array of detectors to execute in order
    DETECTORS = %w(define enum struct typedef function catchall)

    # Given a commented chunk of file, try to parse it.
    def parse_declaration_block(d)
      # skip uncommented declarations
      return unless d[:rawComments].length > 0

      # remove inline comments in declaration
      while comment = d[:body].index("/*") do
        end_comment = d[:body].index("*/", comment)
        d[:body].slice!(comment, end_comment - comment + 2)
      end

      # if there are multiple #ifdef'ed declarations, we'll just
      # strip out the #if/#ifdef and use the first one
      d[:body].sub!(/[^\n]+\n/, '') if d[:body] =~ /\A\#\s*if/

      # try detectors until one assigns a :type to the declaration
      # it's going to be one of:
      # - :define   -> #defines + convert a series of simple ones to :enum
      # - :enum     -> (typedef)? enum { ... };
      # - :struct   -> (typedef)? struct { ... };
      # - :fnptr    -> typedef x (*fn)(...);
      # - :typedef  -> typedef x y; (not enum, struct, fnptr)
      # - :function -> rval something(like this);
      # - :file     -> everything else goes to "file" scope
      DETECTORS.find { |p| method("detect_#{p}").call(d); d.has_key?(:type) }

      # if we detected something, call a parser for that type of thing
      method("parse_#{d[:type]}").call(d) if d[:type]
    end

    # Parse a chunk of text as a header file
    def parse_text(filename, content)
      # break into comments and non-comments with line numbers
      content = "/** */" + content if content[0..2] != "/**"
      recs = []
      lineno = 1
      openblock = false

      content.split(/\/\*\*/).each do |chunk|
        c, b = chunk.split(/[ \t]*\*\//, 2)
        next unless c || b

        lineno += c.scan("\n").length if c

        # special handling for /**< ... */ inline comments or
        # for /** ... */ inside an open block
        if openblock || c[0] == ?<
          c = c.sub(/^</, '').strip

          so_far = recs[-1][:body]
          last_line = so_far[ so_far.rindex("\n")+1 .. -1 ].strip.chomp(",").chomp(";")
          if last_line.empty? && b =~ /^([^;]+)\;/ # apply to this line instead
            last_line = $1.strip.chomp(",").chomp(";")
          end

          if !last_line.empty?
            recs[-1][:inlines] ||= []
            recs[-1][:inlines] << [ last_line, c ]
            if b
              recs[-1][:body] += b
              lineno += b.scan("\n").length
              openblock = false if b =~ /\}/
            end
            next
          end
        end

        # make comment have a uniform " *" prefix if needed
        if c !~ /\A[ \t]*\n/ && c =~ /^(\s*\*)/
          c = $1 + c
        end

        # check for unterminated { brace (to handle inline comments later)
        openblock = true if b =~ /\{[^\}]+\Z/

        recs << {
          :file => filename,
          :line => lineno + (b.start_with?("\n") ? 1 : 0),
          :body => b,
          :rawComments => cleanup_comment(c),
        }

        lineno += b.scan("\n").length if b
      end

      # try parsers on each chunk of commented header
      recs.each do |r|
        r[:body].strip!
        r[:rawComments].strip!
        r[:lineto] = r[:line] + r[:body].scan("\n").length
        parse_declaration_block(r)
      end

      recs
    end
  end
end
