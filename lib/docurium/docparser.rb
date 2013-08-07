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

      args = children(cursor).map do |arg|
        {
          :name => arg.displayName
          :type => arg.type.spelling
        }
      end

      {
        :line => extent.start.line,
        :lineto => extent.end.line,
        :args => args,
      }
    end

    def extract_function_comment(comment)
      text = comment.text
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
