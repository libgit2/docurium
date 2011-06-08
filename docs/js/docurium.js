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
          console.log(this.get('version'))
          this.set({'data': data})
          Backbone.history.start()
        }
      })
    },

    collapseSection: function(data) {
      $(this).next().toggle(100)
    },

    showFun: function(gname, fname) {
      id = '#groupItem' + gname
      ref = parseInt($(id).attr('ref'))

      group = docurium.get('data')['groups'][ref]
      fdata = docurium.get('data')['functions']
      gname = group[0]
      functions = group[1]
      console.log(fdata)
      console.log(ref)

      $('.content').empty()
      $('.content').append($('<h1>').append(fname))
      $('.content').append($('<code>').addClass('params').append('(' + fdata[fname]['args'] + ')'))

      $('.content').append($('<br>'))
      $('.content').append($('<br>'))

      $('.content').append($('<code>').addClass('params').append('returns: ' + fdata[fname]['return']))
      $('.content').append($('<br>'))
      $('.content').append($('<br>'))
      $('.content').append($('<pre>').append(fdata[fname]['comments']))

      $('.content').append($('<hr>'))
      $('.content').append('Also in ' + gname + ':<br/>')

      for(i=0; i<functions.length; i++) {
        f = functions[i]
        d = fdata[f]
        link = $('<a>').attr('href', '#' + groupLink(gname, f)).append(f)
        $('.content').append(link)
        $('.content').append(', ')
      }
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
        row.append($('<td>').attr('nowrap', true).attr('valign', 'top').append(d['return'].substring(0, 20)))
        link = $('<a>').attr('href', '#' + groupLink(gname, f)).append(f)
        row.append($('<td>').attr('valign', 'top').addClass('methodName').append( link ))
        args = d['args'].split(',')
        argtd = $('<td>')
        for(j=0; j<args.length; j++) {
          argtd.append(args[j])
          argtd.append($('<br>'))
        }
        row.append(argtd)
        table.append(row)
      }
      $('.content').append(table)

      for(i=0; i<functions.length; i++) {
        f = functions[i]
        $('.content').append($('<h2>').attr('name', groupLink(gname, f)).append(f).append($('<small>').append(' (' + fdata[f]['args'] + ')')))
        $('.content').append($('<pre>').append(fdata[f]['comments']))
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
      flist = $('<ul>')
      _.each(data['groups'], function(group, i) {
        flink = $('<a href="#" ref="' + i.toString() + '" id="groupItem' + group[0] + '">' + group[0] + ' &nbsp;<small>(' + group[1].length + ')</small></a>')
        flink.click( this.showGroup )
        fitem = $('<li>')
        fitem.append(flink)
        flist.append(fitem)
      }, this)
      menu.append(flist)

      // Data Structures
      title = $('<h3><a href="#">Data Structures</a></h3>').click( this.collapseSection )
      menu.append(title)
      list = $('<ul>')
      menu.append(list)

      // Globals
      title = $('<h3><a href="#">Globals</a></h3>').click( this.collapseSection )
      menu.append(title)
      list = $('<ul>')
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
      ":version/group/:func":         "group",
      ":version/group/:func/:file":   "groupFun",
      ":version/file/*file":          "file",
      ":version/search/:query":       "search",
    },

    group: function(version, gname) {
      docurium.showGroup(null, gname)
    },

    groupFun: function(version, gname, fname) {
      docurium.showFun(gname, fname)
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

    
  window.docurium = new Docurium
  window.ws = new Workspace

  docurium.bind('change:version', function(model, version) {
    $('#version').text(version)
  })
  docurium.bind('change:data', function(model, data) {
    model.refreshView()
  })

})
