class Docurium
  class CLI

    def self.doc(idir, options)
      doc = Docurium.new(idir)
      doc.generate_docs
    end

  end
end
