require 'json'
require 'albino'
require 'pp'

class Docurium
  Version = VERSION = '0.0.1'

  attr_accessor :header_dir, :branch, :output_dir, :valid, :data

  def initialize(dir)
    @valid = false
    @data = {:files => [], :functions => {}}
    if !dir
      puts "You need to specify a directory"
    else
      @valid = true
      @header_dir = File.expand_path(dir)
    end
  end

  def set_function_filter(prefix)
    @prefix_filter = prefix
  end

  def set_branch(branch)
    @branch = branch
  end

  def set_output_dir(dir)
    @output_dir = dir
  end

  def generate_docs
    puts "generating docs from #{@header_dir}"
    puts "parsing headers"
    parse_headers
    if @branch
      write_branch
    else
      write_dir
    end
  end

  def parse_headers
    # TODO: get_version
    headers.each do |header|
      parse_header(header)
    end
    @data[:groups] = group_functions
  end

  private

  def group_functions
    func = {}
    @data[:functions].each_pair do |key, value|
      k = key.gsub(@prefix_filter, '') if @prefix_filter
      group, rest = k.split('_', 2)
      next if group.empty?
      func[group] ||= []
      func[group] << key
      func[group].sort!
    end
    final = {}
    misc = []
    func.each_pair do |group, arr|
      if(arr.length > 1)
        final[group] = arr
      else
        misc += arr
      end
    end
    final = final.to_a.sort
    final << ['misc', misc] if misc.length > 0
    final
  end

  def headers
    h = []
    Dir.chdir(@header_dir) do
      Dir.glob(File.join('**/*.h')).each do |header|
        next if !File.file?(header)
        h << header
      end
    end
    h
  end

  def header_content(header_path)
    File.readlines(File.join(@header_dir, header_path))
  end

  def parse_header(filepath)
    in_comment = false
    current = -1
    lineno = 0
    data = []
    header_content(filepath).each do |line|
      lineno += 1
      line = line.strip
      next if line.size == 0
      next if line[0, 1] == '#' #preprocessor

      if m = /(.*?)\/\*(.*?)\*\//.match(line)
        code = m[1]
        comment = m[2]
        current += 1
        data[current] ||= {:comments => clean_comment(comment), :code => [code], :line => lineno}
      elsif m = /(.*?)\/\/(.*?)/.match(line)
        code = m[1]
        comment = m[2]
        current += 1
        data[current] ||= {:comments => clean_comment(comment), :code => [code], :line => lineno}
      else
        if line =~ /\/\*/
          in_comment = true  
          current += 1
        end
        data[current] ||= {:comments => '', :code => [], :line => lineno}
        if in_comment
          data[current][:comments] += clean_comment(line) + "\n"
        else
          data[current][:code] << line
        end
        in_comment = false if line =~ /\*\//
      end
    end
    meta  = extract_meta(data)
    funcs = extract_functions(filepath, data)
    @data[:files] << {:file => filepath, :meta => meta, :functions => funcs, :lines => lineno}
  end

  def clean_comment(comment)
    comment = comment.gsub(/^\/\//, '')
    comment = comment.gsub(/^\/\**/, '')
    comment = comment.gsub(/^\**/, '')
    comment = comment.gsub(/^[\w\*]*\//, '')
    comment
  end

  # go through all the comment blocks and extract:
  #  @file, @brief, @defgroup and @ingroup
  def extract_meta(data)
    file, brief, defgroup, ingroup = nil
    data.each do |block|
      block[:comments].each do |comment|
        m = []
        file  = m[1] if m = /@file (.*?)$/.match(comment)
        brief = m[1] if m = /@brief (.*?)$/.match(comment)
        defgroup = m[1] if m = /@defgroup (.*?)$/.match(comment)
        ingroup  = m[1] if m = /@ingroup (.*?)$/.match(comment)
      end
    end
    {:file => file, :brief => brief, :defgroup => defgroup, :ingroup => ingroup}
  end

  def extract_functions(file, data)
    @data[:functions]
    funcs = []
    data.each do |block|
      ignore = false
      code = block[:code].join(" ")
      code = code.gsub(/\{(.*)\}/, '') # strip inline code
      rawComments = block[:comments]
      comments = block[:comments]
      if m = /^(.*?) ([a-z_]+)\((.*)\)/.match(code)
        ret  = m[1].strip
        if r = /\((.*)\)/.match(ret) # strip macro
          ret = r[1]
        end
        fun  = m[2].strip
        origArgs = m[3].strip

        # replace ridiculous syntax
        args = origArgs.gsub(/(\w+) \(\*(.*?)\)\(([^\)]*)\)/) do |m|
          type, name = $1, $2
          cast = $3.gsub(',', '###')
          "#{type}(*)(#{cast}) #{name}" 
        end

        args = args.split(',').map do |arg|
          argarry = arg.split(' ')
          var = argarry.pop
          type = argarry.join(' ').gsub('###', ',') + ' '

          ## split pointers off end of type or beg of name
          var.gsub!('*') do |m|
            type += '*'
            ''
          end
          desc = ''
          comments = comments.gsub(/\@param #{Regexp.escape(var)} ([^@]*)/m) do |m|
            desc = $1.gsub("\n", ' ').gsub("\t", ' ').strip
            ''
          end
          ## TODO: parse comments to extract data about args
          {:type => type.strip, :name => var, :comment => desc}
        end

        return_comment = ''
        comments.gsub!(/\@return ([^@]*)/m) do |m|
          return_comment = $1.gsub("\n", ' ').gsub("\t", ' ').strip
          ''
        end

        comments = strip_block(comments)
        comment_lines = comments.split("\n")

        desc = ''
        if comments.size > 0
          desc = comment_lines.shift
          comments = comment_lines.join("\n").strip
        end

        @data[:functions][fun] = {
          :description => desc,
          :return => {:type => ret, :comment => return_comment},
          :args => args,
          :argline => origArgs,
          :file => file,
          :line => block[:line],
          :comments => comments,
          :rawComments => rawComments
        }
        funcs << fun
      end
    end
    funcs
  end

  # TODO: rolled this back, want to strip the first few spaces, not everything
  def strip_block(block)
    block.strip
  end

  def write_branch
    puts "Writing to branch #{@branch}"
    puts "Done!"
  end

  def write_dir
    output_dir = @output_dir || 'docs'
    puts "Writing to directory #{output_dir}"
    here = File.expand_path(File.dirname(__FILE__))

    # files
    # modules
    #
    # functions
    # globals (variables, defines, enums, typedefs)
    # data structures
    #
    FileUtils.mkdir_p(output_dir)
    Dir.chdir(output_dir) do
      FileUtils.cp_r(File.join(here, '..', 'site', '.'), '.') 
      File.open("versions.json", 'w+') do |f|
        f.write(['HEAD'].to_json)
      end
      File.open("HEAD.json", 'w+') do |f|
        f.write(@data.to_json)
      end
      headers.each do |header|
        puts "Highlighting (HEAD):" + header
        content = Albino.colorize(header_content(header).join("\n"), :c)
        FileUtils.mkdir_p(File.join('src/HEAD', File.dirname(header)))
        File.open('src/HEAD/' + header, 'w+') do |f|
          f.write content
        end
      end
    end
    puts "Done!"
  end
end
