$(function() {
  // our document model - stores the datastructure generated from docurium
  var Docurium = Backbone.Model.extend({

    defaults: {'version': 'unknown'},

    initialize: function() {
      this.loadVersions()
    },

    loadVersions: function() {
      $.getJSON("project.json", function(data) {
        docurium.set({'version': 'HEAD', 'versions': data.versions, 'github': data.github})
        docurium.loadDoc()
      })
    },

    loadDoc: function() {
      version = this.get('version')
      $.ajax({
        url: version + '.json',
        context: this,
        dataType: 'json',
        success: function(data){
          this.set({'data': data})
          Backbone.history.start()
        }
      })
    },

    collapseSection: function(data) {
      $(this).next().toggle(100)
      return false
    },

    showIndexPage: function() {
      data = docurium.get('data')
      console.log(data)
      content = $('.content')
      content.empty()

      content.append($('<h1>').append("Public API Functions"))

      // Function Groups
      for (var i in data['groups']) {
        group = data['groups'][i]
        content.append($('<h2>').append(group[0]))
        list = $('<p>').addClass('functionList')
        for(var j in group[1]) {
          fun = group[1][j]
          link = $('<a>').attr('href', '#' + groupLink(group[0], fun)).append(fun)
          list.append(link)
          if(j < group[1].length - 1) {
           list.append(', ')
          }
        }
        content.append(list)
      }
    },

    showFun: function(gname, fname) {
      id = '#groupItem' + gname
      ref = parseInt($(id).attr('ref'))

      group = docurium.get('data')['groups'][ref]
      fdata = docurium.get('data')['functions']
      gname = group[0]
      functions = group[1]

      content = $('.content')
      content.empty()

      content.append($('<h1>').addClass('funcTitle').append(fname))
      if(fdata[fname]['description']) {
        sub = content.append($('<h3>').addClass('funcDesc').append( ' ' + fdata[fname]['description'] ))
      }

      argtable = $('<table>').addClass('funcTable')
      args = fdata[fname]['args']
      for(var i=0; i<args.length; i++) {
        arg = args[i]
        row = $('<tr>')
        row.append($('<td>').attr('valign', 'top').attr('nowrap', true).append(this.hotLink(arg.type)))
        row.append($('<td>').attr('valign', 'top').addClass('var').append(arg.name))
        row.append($('<td>').addClass('comment').append(arg.comment))
        argtable.append(row)
      }
      content.append(argtable)

      retdiv = $('<div>').addClass('returns')
      retdiv.append($('<h3>').append("returns"))
      rettable = $('<table>').addClass('funcTable')
      retrow = $('<tr>')
      rettable.append(retrow)
      retdiv.append(rettable)

      ret = fdata[fname]['return']
      retrow.append($('<td>').attr('valign', 'top').append(this.hotLink(ret.type)))
      if(ret.comment) {
        retrow.append($('<td>').addClass('comment').append(ret.comment))
      }
      content.append(retdiv)

      if (fdata[fname]['comments']) {
        content.append($('<pre>').append(fdata[fname]['comments']))
      }

      ex = $('<code>').addClass('params')
      ex.append(this.hotLink(fdata[fname]['return']['type'] + ' ' + fname + '(' + fdata[fname]['argline'] + ');'))
      example = $('<div>').addClass('example')
      example.append($('<h3>').append("signature"))
      example.append(ex)
      content.append(example)

      also = $('<div>').addClass('also')

      flink = $('<a href="#" ref="' + ref.toString() + '" id="groupItem' + group[0] + '">' + group[0] + '</a>')
      flink.click( docurium.showGroup )
      also.append("Also in ")
      also.append(flink)
      also.append(" group: <br/>")

      for(i=0; i<functions.length; i++) {
        f = functions[i]
        d = fdata[f]
        link = $('<a>').attr('href', '#' + groupLink(gname, f)).append(f)
        also.append(link)
        also.append(', ')
      }

      content.append(also)
      link = this.github_file(fdata[fname].file, fdata[fname].line, fdata[fname].lineto)
      flink = $('<a>').attr('target', 'github').attr('href', link).append(fdata[fname].file)
      content.append($('<div>').addClass('fileLink').append("Defined in: ").append(flink))

      this.addHotlinks()
    },

    showType: function(data, manual) {
      if(manual) {
        id = '#typeItem' + domSafe(manual)
        ref = parseInt($(id).attr('ref'))
      } else {
        ref = parseInt($(this).attr('ref'))
      }
      tdata = docurium.get('data')['types'][ref]
      tname = tdata[0]
      data = tdata[1]

      ws.saveLocation(typeLink(tname))

      content = $('.content')
      content.empty()
      content.append($('<h1>').addClass('funcTitle').append(tname).append($("<small>").append(data.type)))

      content.append($('<p>').append(data.value))
      if(data.block) {
        content.append($('<pre>').append(data.block))
      }

      var ret = data.used.returns
      if (ret.length > 0) {
        content.append($('<h3>').append('Returns'))
      }
      for(var i=0; i<ret.length; i++) {
        gname = docurium.groupOf(ret[i])
        flink = $('<a>').attr('href', '#' + groupLink(gname, ret[i])).append(ret[i])
        flink.click( docurium.showFun )
        content.append(flink)
        content.append(', ')
      }

      var needs = data.used.needs
      if (needs.length > 0) {
        content.append($('<h3>').append('Argument In'))
      }
      for(var i=0; i<needs.length; i++) {
        gname = docurium.groupOf(needs[i])
        flink = $('<a>').attr('href', '#' + groupLink(gname, needs[i])).append(needs[i])
        flink.click( docurium.showFun )
        content.append(flink)
        content.append(', ')
      }

      link = docurium.github_file(data.file, data.line, data.lineto)
      flink = $('<a>').attr('target', 'github').attr('href', link).append(data.file)
      content.append($('<div>').addClass('fileLink').append("Defined in: ").append(flink))

      return false
    },

    showGroup: function(data, manual, flink) {
      if(manual) {
        id = '#groupItem' + manual
        ref = parseInt($(id).attr('ref'))
      } else {
        ref = parseInt($(this).attr('ref'))
      }
      group = docurium.get('data')['groups'][ref]
      fdata = docurium.get('data')['functions']
      gname = group[0]

      ws.saveLocation(groupLink(gname));

      functions = group[1]
      $('.content').empty()
      $('.content').append($('<h1>').append(gname + ' functions'))

      table = $('<table>').addClass('methods')
      for(i=0; i<functions.length; i++) {
        f = functions[i]
        d = fdata[f]
        row = $('<tr>')
        row.append($('<td>').attr('nowrap', true).attr('valign', 'top').append(d['return']['type'].substring(0, 20)))
        link = $('<a>').attr('href', '#' + groupLink(gname, f)).append(f)
        row.append($('<td>').attr('valign', 'top').addClass('methodName').append( link ))
        args = d['args']
        argtd = $('<td>')
        for(j=0; j<args.length; j++) {
          argtd.append(args[j].type + ' ' + args[j].name)
          argtd.append($('<br>'))
        }
        row.append(argtd)
        table.append(row)
      }
      $('.content').append(table)

      for(var i=0; i<functions.length; i++) {
        f = functions[i]
        argsText = '( ' + fdata[f]['argline'] + ' )'
        link = $('<a>').attr('href', '#' + groupLink(gname, f)).append(f)
        $('.content').append($('<h2>').append(link).append($('<small>').append(argsText)))
        $('.content').append($('<pre>').append(fdata[f]['rawComments']))
      }
      return false
    },

    // look for structs and link them 
    hotLink: function(text) {
      types = this.get('data')['types']
      for(var i=0; i<types.length; i++) {
        type = types[i]
        typeName = type[0]
        typeData = type[1]
        re = new RegExp(typeName + ' ', 'gi');
        link = '<a ref="' + i.toString() + '" class="typeLink' + domSafe(typeName) + '" href="#">' + typeName + '</a> '
        text = text.replace(re, link)
      }
      return text
    },

    groupHash: false,
    groupOf: function (func) {
      if(!this.groupHash) {
        this.groupHash = {}
        data = this.get('data')
        for(var i=0; i<data['groups'].length; i++) {
          group = data['groups'][i][1]
          groupName = data['groups'][i][0]
          for(var j=0; j<group.length; j++) {
            f = group[j]
            this.groupHash[f] = groupName
          }
        }
      }
      return this.groupHash[func]
    },

    addHotlinks: function() {
      types = this.get('data')['types']
      for(var i=0; i<types.length; i++) {
        type = types[i]
        typeName = type[0]
        className = '.typeLink' + domSafe(typeName)
        $(className).click( this.showType )
      }
    },

    refreshView: function() {
      data = this.get('data')

      // Function Groups
      menu = $('<li>')
      title = $('<h3><a href="#">Functions</a></h3>').click( this.collapseSection )
      menu.append(title)
      list = $('<ul>')
      _.each(data['groups'], function(group, i) {
        flink = $('<a href="#" ref="' + i.toString() + '" id="groupItem' + group[0] + '">' + group[0] + ' &nbsp;<small>(' + group[1].length + ')</small></a>')
        flink.click( this.showGroup )
        fitem = $('<li>')
        fitem.append(flink)
        list.append(fitem)
      }, this)
      menu.append(list)

      // Types
      title = $('<h3><a href="#">Types</a></h3>').click( this.collapseSection )
      menu.append(title)
      list = $('<ul>')

      fitem = $('<li>')
      fitem.append($('<span>').addClass('divide').append("Enums"))
      list.append(fitem)

      _.each(data['types'], function(group, i) {
        if(group[1]['block'] && group[1]['type'] == 'enum') {
          flink = $('<a href="#" ref="' + i.toString() + '" id="typeItem' + domSafe(group[0]) + '">' + group[0]  + '</a>')
          flink.click( this.showType )
          fitem = $('<li>')
          fitem.append(flink)
          list.append(fitem)
        }
      }, this)

      fitem = $('<li>')
      fitem.append($('<span>').addClass('divide').append("Public Struct"))
      list.append(fitem)

      _.each(data['types'], function(group, i) {
        if(group[1]['block'] && group[1]['type'] != 'enum') {
          flink = $('<a href="#" ref="' + i.toString() + '" id="typeItem' + domSafe(group[0]) + '">' + group[0]  + '</a>')
          flink.click( this.showType )
          fitem = $('<li>')
          fitem.append(flink)
          list.append(fitem)
        }
      }, this)

      fitem = $('<li>')
      fitem.append($('<span>').addClass('divide').append("Private Struct"))
      list.append(fitem)

      _.each(data['types'], function(group, i) {
        if(!group[1]['block']) {
          flink = $('<a href="#" ref="' + i.toString() + '" id="typeItem' + domSafe(group[0]) + '">' + group[0]  + '</a>')
          flink.click( this.showType )
          fitem = $('<li>')
          fitem.append(flink)
          list.append(fitem)
        }
      }, this)
      list.hide()
      menu.append(list)

      // File Listing
      title = $('<h3><a href="#">Files</a></h3>').click( this.collapseSection )
      menu.append(title)
      filelist = $('<ul>')
      _.each(data['files'], function(file) {
        url = this.github_file(file['file'])
        flink = $('<a target="github" href="' + url + '">' + file['file'] + '</a>')
        fitem = $('<li>')
        fitem.append(flink)
        filelist.append(fitem)
      }, this)
      filelist.hide()
      menu.append(filelist)

      list = $('#files-list')
      list.empty()
      list.append(menu)
    },

    github_file: function(file, line, lineto) {
      url = "https://github.com/" + docurium.get('github')
      url += "/blob/" + docurium.get('version') + '/' + data.prefix + '/' + file
      if(line) {
        url += '#L' + line.toString()
        if(lineto) {
          url += '-' + lineto.toString()
        }
      } else {
        url += '#files'
      }
      return url
    },

    search: function(data) {
      var searchResults = []
      var value = $('#search-field').attr('value')
      if (value.length < 3) {
        return false
      }
      this.searchResults = []

      ws.saveLocation(searchLink(value))

      data = docurium.get('data')

      // look for functions (name, comment, argline)
      for (var name in data.functions) {
        f = data.functions[name]
        if (name.search(value) > -1) {
          gname = docurium.groupOf(name)
          var flink = $('<a>').attr('href', '#' + groupLink(gname, name)).append(name)
          searchResults.push(['fun-' + name, flink, 'function'])
        }
        if (f.argline) {
          if (f.argline.search(value) > -1) {
            gname = docurium.groupOf(name)
            var flink = $('<a>').attr('href', '#' + groupLink(gname, name)).append(name)
            searchResults.push(['fun-' + name, flink, f.argline])
          }
        }
      }
      for (var i in data.types) {
        var type = data.types[i]
        name = type[0]
        if (name.search(value) > -1) {
          var link = $('<a>').attr('href', '#' + typeLink(name)).append(name)
          searchResults.push(['type-' + name, link, type[1].type])
        }
      }

      // look for types
      // look for files
      content = $('.content')
      content.empty()

      content.append($('<h1>').append("Search Results"))
      table = $("<table>")
      var shown = {}
      for (var i in searchResults) {
        row = $("<tr>")
        result = searchResults[i]
        if (!shown[result[0]]) {
          link = result[1]
          match = result[2]
          row.append($('<td>').append(link))
          row.append($('<td>').append(match))
          table.append(row)
          shown[result[0]] = true
        }
      }
      content.append(table)

    }

  })

  var Workspace = Backbone.Controller.extend({

    routes: {
      "":                             "main",
      ":version/group/:group":        "group",
      ":version/type/:type":          "showtype",
      ":version/group/:group/:func":  "groupFun",
      ":version/search/:query":       "search",
    },

    main: function() {
      docurium.showIndexPage()
    },

    group: function(version, gname) {
      docurium.showGroup(null, gname)
    },

    groupFun: function(version, gname, fname) {
      docurium.showFun(gname, fname)
    },

    showtype: function(version, tname) {
      docurium.showType(null, tname)
    },

    search: function(version, query) {
      $('#search-field').attr('value', query)
      docurium.search()
    },

  });

  function groupLink(gname, fname) {
    if(fname) {
      return docurium.get('version') + "/group/" + gname + '/' + fname
    } else {
      return docurium.get('version') + "/group/" + gname
    }
  }

  function typeLink(tname) {
    return docurium.get('version') + "/type/" + tname
  }

  function searchLink(tname) {
    return docurium.get('version') + "/search/" + tname
  }

  function domSafe(str) {
    return str.replace('_', '-')
  }

    
  window.docurium = new Docurium
  window.ws = new Workspace

  docurium.bind('change:version', function(model, version) {
    $('#version').text(version)
  })
  docurium.bind('change:data', function(model, data) {
    model.refreshView()
  })

  $('#search-field').keyup( docurium.search )
  $('#logo').click( docurium.showIndexPage )

})
