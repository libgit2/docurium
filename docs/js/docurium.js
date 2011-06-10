$(function() {
  // our document model - stores the datastructure generated from docurium
  var Docurium = Backbone.Model.extend({

    defaults: {'version': 'unknown'},

    initialize: function() {
      this.loadVersions()
    },

    loadVersions: function() {
      $.get("versions.json", function(data) {
        docurium.set({'version': 'HEAD', 'versions': data})
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
      for(i=0; i<args.length; i++) {
        row = $('<tr>')
        row.append($('<td>').attr('valign', 'top').attr('nowrap', true).append(args[i].type))
        row.append($('<td>').attr('valign', 'top').addClass('var').append(args[i].name))
        row.append($('<td>').addClass('comment').append(args[i].comment))
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
      retrow.append($('<td>').attr('valign', 'top').append(ret.type))
      if(ret.comment) {
        retrow.append($('<td>').addClass('comment').append(ret.comment))
      }
      content.append(retdiv)

      if (fdata[fname]['comments']) {
        content.append($('<pre>').append(fdata[fname]['comments']))
      }

      ex = $('<code>').addClass('params')
      ex.append(fdata[fname]['return']['type'] + ' ' + fname + '(' + fdata[fname]['argline'] + ');')
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

      ws.saveLocation(typeLink(tname))

      data = tdata[1]
      $('.content').empty()
      $('.content').append($('<h1>').append(tname))

      $('.content').append($('<p>').append(data.type))
      $('.content').append($('<p>').append(data.value))
      if(data.block) {
        $('.content').append($('<pre>').append(data.block))
      }
      $('.content').append($('<p>').append(data.file + ':' + data.line))

      console.log(data)

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

      for(i=0; i<functions.length; i++) {
        f = functions[i]
        argsText = '( ' + fdata[f]['argline'] + ' )'
        link = $('<a>').attr('href', '#' + groupLink(gname, f)).append(f)
        $('.content').append($('<h2>').append(link).append($('<small>').append(argsText)))
        $('.content').append($('<pre>').append(fdata[f]['rawComments']))
      }
      return false
    },

    loadFile: function(data) {
      $.ajax({
        url: $(this).attr('href'),
        context: this,
        success: function(data){
          $(".content").html('<h1>' + $(this).text() + '</h1>')
          $(".content").append(data)
        }
      })
      return false
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
      list.hide()
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
      //list.hide()
      menu.append(list)

      // File Listing
      title = $('<h3><a href="#">Files</a></h3>').click( this.collapseSection )
      menu.append(title)
      filelist = $('<ul>')
      _.each(data['files'], function(file) {
        flink = $('<a href="/src/' + this.get('version') + '/' + file['file'] + '">' + file['file'] + '</a>')
        flink.click( this.loadFile )
        fitem = $('<li>')
        fitem.append(flink)
        filelist.append(fitem)
      }, this)
      filelist.hide()
      menu.append(filelist)

      list = $('#files-list')
      list.empty()
      list.append(menu)
    }

  })

  var Workspace = Backbone.Controller.extend({

    routes: {
      ":version/group/:group":        "group",
      ":version/type/:type":          "showtype",
      ":version/group/:group/:func":  "groupFun",
      ":version/file/*file":          "file",
      ":version/search/:query":       "search",
    },

    group: function(version, gname) {
      docurium.showGroup(null, gname)
    },

    groupFun: function(version, gname, fname) {
      docurium.showFun(gname, fname)
    },

    showtype: function(version, tname) {
      console.log("SHOWTYPE")
      docurium.showType(null, tname)
    },

    file: function(version, fname) {
      docurium.showFile(null, fname)
    },

    search: function(version, query) {
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

})
