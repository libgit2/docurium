require 'tempfile'
require 'fileutils'
require 'ffi/clang'
require 'open3'
include FFI::Clang

class Docurium
  class DocParser
    # The include directory where clang has its basic type definitions is not
    # included in our default search path, so as a workaround we execute clang
    # in verbose mode and grab its include paths from the output.
    def find_clang_includes
      @includes ||=
        begin
          clang = if ENV["LLVM_CONFIG"]
            bindir = `#{ENV["LLVM_CONFIG"]} --bindir`.strip
            "#{bindir}/clang"
          else
            "clang"
          end

          output, _status = Open3.capture2e("#{clang} -v -x c -", :stdin_data => "")
          includes = []
          output.each_line do |line|
            if line =~ %r{^\s+/(.*usr|.*lib/clang.*)/include}
              includes << line.strip
            end
          end

          includes
        end
    end

    def self.with_files(files, opts = {})
      parser = self.new(files, opts)
      yield parser
      parser.cleanup!
    end

    def initialize(files, opts = {})
      # unfortunately Clang wants unsaved files to exist on disk, so
      # we need to create at least empty files for each unsaved file
      # we're given.

      prefix = (opts[:prefix] ? opts[:prefix] + "-" : nil)
      @tmpdir = Dir.mktmpdir(prefix)
      @unsaved = files.map do |name, contents|
        full_path = File.join(@tmpdir, name)
        dirname = File.dirname(full_path)
        FileUtils.mkdir_p(dirname) unless Dir.exist? dirname
        File.new(full_path, File::CREAT).close()
        UnsavedFile.new(full_path, contents)
      end
    end

    def cleanup!
      FileUtils.remove_entry(@tmpdir)
    end

    # Entry point for this parser
    # Parse `filename` out of the hash `files`
    def parse_file(orig_filename, opts = {})

      includes = find_clang_includes + [@tmpdir]

      # Override the path we want to filter by
      filename = File.join(@tmpdir, orig_filename)
      debug_enable if opts[:debug]
      debug "parsing #{filename} #{@tmpdir}"
      args = includes.map { |path| "-I#{path}" }
      args << '-ferror-limit=1'

      tu = Index.new(true, true).parse_translation_unit(filename, args, @unsaved, {:detailed_preprocessing_record => 1})

      recs = []

      tu.cursor.visit_children do |cursor, parent|
        location = cursor.location
        next :continue if location.file == nil
        next :continue unless location.file == filename

        loc = "%d:%d-%d:%d" % [cursor.extent.start.line, cursor.extent.start.column, cursor.extent.end.line, cursor.extent.end.column]
        debug "#{cursor.location.file}:#{loc} - visiting #{cursor.kind}: #{cursor.spelling}, comment is #{cursor.comment.kind}"

        #cursor.visit_children do |c|
        #  puts "  child #{c.kind}, #{c.spelling}, #{c.comment.kind}"
        #  :continue
        #end

        next :continue if cursor.spelling == ""

        extent = cursor.extent
        rec = {
          :file => orig_filename,
          :line => extent.start.line,
          :lineto => extent.end.line,
          :tdef => nil,
        }

        extract = case cursor.kind
        when :cursor_function
          debug "have function #{cursor.spelling}"
          rec.update extract_function(cursor)
        when :cursor_enum_decl
          debug "have enum #{cursor.spelling}"
          rec.update extract_enum(cursor)
        when :cursor_struct
          debug "have struct #{cursor.spelling}"
          rec.update extract_struct(cursor)
        when :cursor_typedef_decl
          debug "have typedef #{cursor.spelling} #{cursor.underlying_type.spelling}"
          rec.update extract_typedef(cursor)
        when :cursor_variable
          next :continue
        when :cursor_macro_definition
          next :continue
        when :cursor_inclusion_directive
          next :continue
        when :cursor_macro_expansion
          next :continue
        else
          raise "No idea how to deal with #{cursor.kind}"
        end

        rec.merge! extract

        recs << rec
        :continue
      end

      if debug_enabled
        puts "parse_file: parsed #{recs.size} records for #{filename}:"
        recs.each do |r|
          puts "\t#{r}"
        end
      end

      debug_restore

      recs
    end

    def extract_typedef(cursor)
      child = nil
      cursor.visit_children { |c| child = c; :break }
      rec = {
        :name => cursor.spelling,
        :underlying_type => cursor.underlying_type.spelling,
        :tdef => :typedef,
      }

      if not child
        return rec
      end

      #puts "have typedef #{child.kind}, #{cursor.extent.start.line}"
      case child.kind
      when :cursor_type_ref
        #puts "pure typedef, #{cursor.spelling}"
        if child.type.kind == :type_record
          rec[:type] = :struct
          subject, desc = extract_subject_desc(cursor.comment)
          rec[:decl] = cursor.spelling
          rec[:description] = subject
          rec[:comments] = desc
        else
          rec[:name] = cursor.spelling
        end
      when :cursor_enum_decl
        rec.merge! extract_enum(child)
      when :cursor_struct
        #puts "typed struct, #{cursor.spelling}"
        rec.merge! extract_struct(child)
      when :cursor_parm_decl
        rec.merge! extract_function(cursor)
        rec[:type] = :callback
        # this is wasteful, but we don't get the array from outside
        cmt = extract_function_comment(cursor.comment)
        ret = {
               :type => extract_callback_result(rec[:underlying_type]),
               :comment => cmt[:return]
              }
        rec[:return] = ret
      else
        raise "No idea how to handle #{child.kind}"
      end
      # let's make sure we override the empty name the extract
      # functions stored
      rec[:name] = cursor.spelling
      rec
    end

    def extract_callback_result(type)
      type[0..(type.index('(') - 1)].strip
    end

    def extract_function_args(cursor, cmt)
      # We only want to look at parm_decl to avoid looking at a return
      # struct as a parameter
      children(cursor)
        .select {|c| c.kind == :cursor_parm_decl }
        .map do |arg|
        {
          :name => arg.display_name,
          :type => arg.type.spelling,
          :comment => cmt[:args][arg.display_name],
        }
      end
    end

    def extract_subject_desc(comment)
      subject = comment.child.text
      debug "\t\tsubject: #{subject}"
      paras = comment.find_all { |cmt| cmt.kind == :comment_paragraph }.drop(1).map { |p| p.text }
      desc = paras.join("\n\n")
      debug "\t\tdesc: #{desc}"
      return subject, desc
    end

    def extract_function(cursor)
      comment = cursor.comment

      $buggy_functions = %w()
      debug_set ($buggy_functions.include? cursor.spelling)
      if debug_enabled
        puts "\tlooking at function #{cursor.spelling}, #{cursor.display_name}"
        puts "\tcomment: #{comment}, #{comment.kind}"
        cursor.visit_children do |cur, parent|
          puts "\t\tchild: #{cur.spelling}, #{cur.kind}"
          :continue
        end
      end

      cmt = extract_function_comment(comment)
      args = extract_function_args(cursor, cmt)
      #args = args.reject { |arg| arg[:comment].nil? }

      ret = {
        :type => cursor.result_type.spelling,
        :comment => cmt[:return]
      }

      # generate function signature
      sig = args.map { |a| a[:type].to_s }.join('::')

      argline = args.map { |a|
        # pointers don't have a separation between '*' and the name
        if a[:type].end_with? "*"
          "#{a[:type]}#{a[:name]}"
        else
          "#{a[:type]} #{a[:name]}"
        end
      }.join(', ')

      decl = "#{ret[:type]} #{cursor.spelling}(#{argline})"
      body = "#{decl};"

      debug_restore
      #puts cursor.display_name
      # Return the format that docurium expects
      {
        :type => :function,
        :name => cursor.spelling,
        :body => body,
        :description => cmt[:description],
        :comments => cmt[:comments],
        :sig => sig,
        :args => args,
        :return => ret,
        :decl => decl,
        :argline => argline
      }
    end

    def extract_function_comment(comment)
      subject, desc = extract_subject_desc(comment)
      debug "\t\textract_function_comment: #{comment}, #{comment.kind}, #{subject}, #{desc}"

      args = {}
      (comment.find_all { |cmt| cmt.kind == :comment_param_command }).each do |param|
        args[param.name] = param.comment.strip
      end

      ret = nil
      comment.each do |block|
        next unless block.kind == :comment_block_command
        next unless block.name == "return"

        ret = block.paragraph.text

        break
      end

      {
        :description => subject,
        :comments => desc,
        :args => args,
        :return => ret,
      }
    end

    def extract_fields(cursor)
      fields = []
      cursor.visit_children do |cchild, cparent|
        field = {
          :type => cchild.type.spelling,
          :name => cchild.spelling,
          :comments => cchild.comment.find_all {|c| c.kind == :comment_paragraph }.map(&:text).join("\n\n")
        }

        if cursor.kind == :cursor_enum_decl
          field.merge!({:value => cchild.enum_value})
        end

        fields << field
        :continue
      end

        fields
    end

    def extract_enum(cursor)
      subject, desc = extract_subject_desc(cursor.comment)

      decl = []
      cursor.visit_children do |cchild, cparent|
        decl << cchild.spelling
        :continue
      end

      block = decl.join("\n")
      #return the docurium object
      {
        :type => :enum,
        :name => cursor.spelling,
        :description => subject,
        :comments => desc,
        :fields => extract_fields(cursor),
        :block => block,
        :decl => decl,
      }
    end

    def extract_struct(cursor)
      subject, desc = extract_subject_desc(cursor.comment)

      values = []
      cursor.visit_children do |cchild, cparent|
        values << "#{cchild.type.spelling} #{cchild.spelling}"
        :continue
      end

      debug "\tstruct value #{values}"

      rec = {
        :type => :struct,
        :name => cursor.spelling,
        :description => subject,
        :comments => desc,
        :fields => extract_fields(cursor),
        :decl => values,
      }

      rec[:block] = values.join("\n") unless values.empty?
      rec
    end

    def children(cursor)
      list = []
      cursor.visit_children do |ccursor, cparent|
        list << ccursor
        :continue
      end

      list
    end

  end
end
