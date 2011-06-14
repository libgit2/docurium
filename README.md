# Docurium

Docurium is a lightweight Doxygen replacement.  It generates static HTML from the header files of a C project. It is meant to be simple, easy to navigate and git-tag aware. It is only meant to document your public interface, so it only knows about your header files.

I built it to replace the Doxygen generated documentation for the libgit2 project, so I'm only currently testing it against that.  So, it is only known to include support for features and keywords used in that project currently.  If you have a C library project you try this on and something is amiss, please file an issue or better yet, a pull request.

Though Docurium can generate your docs into a subdirectory, it is meant to be served from a webserver, not locally.  It uses XMLHttpRequest calls, which cannot be done locally, so you can't just open the index.html file locally and have it work - you need to either run a webserver in the output directory or push it to a website to view it properly.  I use Pow (pow.cx) or GitHub Pages.

# Usage

Run the `cm` binary and pass it your Docurium config file.

    $ cm doc api.docurium
    * generating docs
      - processing version v0.1.0
      - processing version v0.2.0
      - processing version v0.3.0
      - processing version v0.8.0
      - processing version v0.10.0
      - processing version v0.11.0
      - processing version v0.12.0
      - processing version HEAD
    * output html in docs/

The Docurium config file looks like this:

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

# Installing

    $ gem install docurium

# Screenshots

![Main Page](https://img.skitch.com/20110614-c98pp6c9p9mn35jn4iskjim7hk.png)

![Func Page](https://img.skitch.com/20110614-mdasyhip3swxtngwxrce8wqy3h.png)

# Contributing

If you want to fix or change something, please fork on GitHub, push your change to a branch named after your change and send me a pull request.

# License

MIT, see LICENCE file


# vim:ft=markdown
