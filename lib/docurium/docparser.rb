require 'ffi/clang'
import FFI::Clang

class Docurium
  class DocParser
    # Entry point for this parser
    # Parse `name` out of the hash `files`
    def parse_file(filename, files)

      tu = Index.new.parse_translation_unit(filename, nil, unsaved_files(files))
      cursor = tu.cursor

      cursor.visit_children do |cursor, parent|
        location = cursor.location
        next :continue unless location.file == filename
        next :continue if cursor.comment.kind == :comment_null

        case cursor.kind
        when :cursor_function
          extract_function(cursor)
        end
      end

    end

    def extract_function(cursor)
      comment = cursor.comment
      extent = cursor.extent

      cmt = extract_function_comment(cursor)

      args = children(cursor).map do |arg|
        {
          :name => arg.display_name,
          :type => arg.type.spelling,
          :comment => cmt[:args][arg.display_name],
        }
      end

      ret = {
        :type => cursor.result_type.spelling,
        :comment => cmt[:return]
      }

      # generate function signature
      sig = d[:args].map { |a| a[:type].to_s }.join('::')

      # Return the format that docurium expects
      {
        :sig = sig,
        :line => extent.start.line,
        :lineto => extent.end.line,
        :args => args,
        :return => ret,
      }
    end

    def extract_function_comment(comment)
      subject = comment.child.text
      desc = comment.find_all { |cmt| cmt.kind == :comment_paragraph }
      long = (desc.drop(1).map do |para|
                para.text
              end).join("\n")

      args = {}
      (comment.find_all { |cmt| cmd.kind == :comment_param_command }).each do |param|
        args[param.display_name] = param.comment.strip
      end

      ret = nil
      comment.each do |block|
        next unless :comment_block_command
        next unless block.name != "return"

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
