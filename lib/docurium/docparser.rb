require 'ffi/clang'
include FFI::Clang

class Docurium
  class DocParser
    # Entry point for this parser
    # Parse `filename` out of the hash `files`
    def parse_file(filename, files)
      puts "called for #{filename}"
      tu = Index.new.parse_translation_unit(filename, ["-Igit2"], unsaved_files(files), {:detailed_preprocessing_record => 1})
      cursor = tu.cursor

      recs = []
      cursor.visit_children do |cursor, parent|
        puts "visiting #{cursor.kind} - #{cursor.spelling}"
        location = cursor.location
        next :continue unless location.file == filename
        next :continue if cursor.comment.kind == :comment_null
        next :continue if cursor.spelling == ""

        extent = cursor.extent
        rec = {
          :file => filename,
          :line => extent.start.line,
          :lineto => extent.end.line,
        }

        case cursor.kind
        when :cursor_function
          puts "have function"
          rec.merge! extract_function(cursor)
        when :cursor_enum_decl
          rec.merge! extract_enum(cursor)
        when :cursor_struct
          puts "raw struct"
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
      rec = {}
      puts "have typedef #{child.kind}, #{cursor.extent.start.line}"
      case child.kind
      when :cursor_typeref
        puts "pure typedef, #{cursor.spelling}"
        extent = cursor.extent
        rec = {
          :type => :typedef,
          :name => cursor.spelling,
        }
      when :cursor_enum_decl
        rec = extract_enum(child)
      when :cursor_struct
        puts "typed struct, #{cursor.spelling}"
        rec = extract_struct(child)
      when :cursor_parm_decl
        puts "have parm #{cursor.spelling}, #{cursor.display_name}"
        extent = child.extent
        rec = {
          :decl => cursor.spelling,
        }
        rec.merge! extract_comments(cursor)
      else
        raise "No idea how to handle #{child.kind}"
      end
      rec[:name] = cursor.spelling
      rec[:tdef] = cursor.spelling
      rec
    end

    def extract_function(cursor)
      comment = cursor.comment

      puts "looking at function #{cursor.spelling}, #{cursor.display_name}"
      cmt = extract_function_comment(comment)

      # clang gives us CXCursor_FirstAttr as the first one, so we need
      # to skip it
      args = children(cursor).drop(1).map do |arg|
        {
          :name => arg.display_name,
          :type => arg.type.spelling,
          :comment => cmt[:args][arg.display_name],
        }
      end
      args = args.reject { |arg| arg[:comment].nil? }

      ret = {
        :type => cursor.result_type.spelling,
        :comment => cmt[:return]
      }

      # generate function signature
      sig = args.map { |a| a[:type].to_s }.join('::')

      puts cursor.display_name
      # Return the format that docurium expects
      {
        :type => :function,
        :name => cursor.spelling,
        :description => cmt[:description],
        :comments => cmt[:comments],
        :sig => sig,
        :args => args,
        :return => ret,
        :argline => cursor.display_name # FIXME: create a real argline
      }
    end

    def extract_function_comment(comment)
      subject = comment.child.text
      desc = comment.find_all { |cmt| cmt.kind == :comment_paragraph }
      long = (desc.drop(1).map do |para|
                para.text
              end).join("\n")

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
        :comments => long,
        :args => args,
        :return => ret,
      }
    end

    def extract_enum(cursor)
      comment = cursor.comment
      subject = comment.child.text
      desc = comment.find_all { |cmt| cmt.kind == :comment_paragraph }
      long = (desc.map do |para|
                para.text
              end).join("\n")

      values = []
      cursor.visit_children do |cchild, cparent|
        values << cchild.spelling
        :continue
      end

      block = values.join("\n")
      #return the docurium object
      {
        :type => :enum,
        :name => cursor.spelling,
        :description => subject,
        :comments => long,
        :block => block,
        :decl => values,
      }
    end

    def extract_struct(cursor)
      comment = cursor.comment
      puts " comment #{comment.kind}, child #{comment.child.kind}"
      subject = comment.child.text
      puts " subject #{subject}"
      desc = comment.find_all { |cmt| cmt.kind == :comment_paragraph }
      long = (desc.map do |para|
                para.text
              end).join("\n")

      values = []
      cursor.visit_children do |cchild, cparent|
        values << cchild.spelling
        :continue
      end

      puts "struct values #{values}"

      {
        :type => :struct,
        :name => cursor.spelling,
        :description => subject,
        :comments => long,
        :decl => values,
      }
    end

    # For standard comment types
    def extract_comments(cursor)
      comment = cursor.comment
      subject = comment.child.text
      desc = comment.find_all { |cmt| cmt.kind == :comment_paragraph }
      long = (desc.map do |para|
                para.text
              end).join("\n")

      {
        :subject => subject,
        :long => long,
      }
    end

    def children(cursor)
      list = []
      cursor.visit_children do |ccursor, cparent|
        list << ccursor
        :continue
      end

      list
    end

    def unsaved_files(files)
      files.map do |name, content|
        UnsavedFile.new("git2/#{name}", content)
      end
    end

  end
end
