class Docurium
  class CLI

    def self.doc(idir, options)
      doc = Docurium.new(idir)
      doc.generate_docs(options)
    end

    def self.check(idir, options)
      doc = Docurium.new(idir)
      doc.check_warnings(options)
    end

    def self.gen(file)

temp = <<-TEMPLATE
{
 "name":   "project",
 "github": "user/project",
 "input":  "include/lib",
 "prefix": "lib_",
 "branch": "gh-pages"
}
TEMPLATE
      puts "Writing to #{file}"
      File.open(file, 'w+') do |f|
        f.write(temp)
      end
    end

  end
end
