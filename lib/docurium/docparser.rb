require 'tempfile'
require 'fileutils'
require 'ffi/clang'
include FFI::Clang

class Docurium
  class DocParser
    # Entry point for this parser
    # Parse `filename` out of the hash `files`
    def parse_file(orig_filename, files)

      # unfortunately Clang wants unsaved files to exist on disk, so
      # we need to create at least empty files for each unsaved file
      # we're given.

      tmpdir = Dir.mktmpdir()

      unsaved = files.map do |name, contents|
        full_path = File.join(tmpdir, name)
        dirname = File.dirname(full_path)
        FileUtils.mkdir_p(dirname) unless Dir.exist? dirname
        File.new(full_path, File::CREAT).close()

        UnsavedFile.new(full_path, contents)
      end

      # Override the path we want to filter by
      filename = File.join(tmpdir, orig_filename)
      tu = Index.new(true, true).parse_translation_unit(filename, ["-DDOCURIUM=1"], unsaved, {:detailed_preprocessing_record => 1})

      FileUtils.remove_entry(tmpdir)

      recs = []

      tu.cursor.visit_children do |cursor, parent|
        #puts "visiting #{cursor.kind} - #{cursor.spelling}"
        location = cursor.location
        next :continue if location.file == nil
        next :continue unless location.file == filename

        #puts "for file #{location.file} #{cursor.kind} #{cursor.spelling} #{cursor.comment.kind} #{location.line}"
        #cursor.visit_children do |c|
        #  puts "  child #{c.kind}, #{c.spelling}, #{c.comment.kind}"
        #  :continue
        #end

        next :continue if cursor.comment.kind == :comment_null
        next :continue if cursor.spelling == ""

        extent = cursor.extent
        rec = {
          :file => orig_filename,
          :line => extent.start.line,
          :lineto => extent.end.line,
          :tdef => nil,
        }

        case cursor.kind
        when :cursor_function
          #puts "have function"
          rec.merge! extract_function(cursor)
        when :cursor_enum_decl
          rec.merge! extract_enum(cursor)
        when :cursor_struct
          #puts "raw struct"
          rec.merge! extract_struct(cursor)
        when :cursor_typedef_decl
          rec.merge! extract_typedef(cursor)
        else
          raise "No idea how to deal with #{cursor.kind}"
        end

        recs << rec
        :continue
      end

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
      paras = comment.find_all { |cmt| cmt.kind == :comment_paragraph }.drop(1).map { |p| p.text }
      desc = paras.join("\n\n")
      return subject, desc
    end

    def extract_function(cursor)
      comment = cursor.comment

      #puts "looking at function #{cursor.spelling}, #{cursor.display_name}"
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

      #puts "struct value #{values}"

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
