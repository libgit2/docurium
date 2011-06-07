class Docurium
  class CLI

    def self.doc(idir, options)
      doc = Docurium.new(idir)
      if doc.valid
        doc.set_function_filter(options[:f]) if options[:f]
        if options[:b]
          doc.set_branch(options[:b])
        elsif options[:o]
          doc.set_output_dir(options[:o])
        end
        doc.generate_docs
      end
    end

  end
end
