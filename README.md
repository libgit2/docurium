# Docurium

Docurium is a lightweight Doxygen replacement.  It generates static HTML from the header files of a C project. It is meant to be simple, easy to navigate and git-tag aware. It is only meant to document your public interface, so it only knows about your header files.

I built it to replace the Doxygen generated documentation for the libgit2 project, so I'm only currently testing it against that.  So, it only includes support for features and keywords used in that project currently.

# Usage

Run the `cm` binary and pass it your Docurium config file.

    $ cm doc api.docurium
    * generating header based docs
      - processing limit.h
      - processing recess.h
    * output html in docs/

The Docurium config files looks like this:

    {
     "name":   "libgit2",
     "github": "libgit2/libgit2",
     "input":  "include/git2",
     "prefix": "git_",
     "output": "docs",
     "legacy":  {
        "input": {"src/git": ["v0.1.0"],
                  "src/git2": ["v0.2.0", "v0.3.0"]}
      }
    }

# License

MIT, see LICENCE file


