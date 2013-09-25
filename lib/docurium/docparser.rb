require 'ffi/clang'
include FFI::Clang

class Docurium
  class DocParser
    # Entry point for this parser
    # Parse `filename` out of the hash `files`
    def parse_file(filename, files)

      tu = Index.new.parse_translation_unit(filename, nil, unsaved_files(files))
      cursor = tu.cursor

      recs = []
      cursor.visit_children do |cursor, parent|
        location = cursor.location
        next :continue unless location.file == filename
        next :continue if cursor.comment.kind == :comment_null
        next :continue if cursor.spelling == ""

        case cursor.kind
        when :cursor_function
          rec = extract_function(cursor)
          rec[:file] = filename
          recs << rec
        when :cursor_enum_decl
          puts "raw enum #{cursor.spelling}, #{filename}"
          rec = extract_enum(cursor)
          rec[:file] = filename
          recs << rec
        when :cursor_typedef_decl
          child = nil
          cursor.visit_children { |c| child = c; :break }
          puts "typedef of #{child.kind}"
          if child.kind == :cursor_enum_decl
            rec = extract_enum(child)
            rec[:file] = filename
            rec[:name] = cursor.spelling
            recs << rec
          end
          # A couple of levels deep we can get to the enum and we
          # should be able to extract it with the above function
        end

        :continue
      end

      recs
    end

    def extract_function(cursor)
      comment = cursor.comment
      extent = cursor.extent

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
        :line => extent.start.line,
        :lineto => extent.end.line,
        :args => args,
        :return => ret,
        :argline => cursor.display_name
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
      extent = cursor.extent
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
        :line => extent.start.line,
        :lineto => extent.end.line,
        :block => block,
        :decl => ["foo"], #FIXME
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
        UnsavedFile.new(name, content)
      end
    end

  end
end
