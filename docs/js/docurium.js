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

    showGroup: function(data, manual) {
      if(manual) {
        id = '#groupItem' + manual
        ref = parseInt($(id).attr('ref'))
      } else {
        ref = parseInt($(this).attr('ref'))
      }
      group = docurium.get('data')['groups'][ref]
      fdata = docurium.get('data')['functions']
      gname = group[0]
      functions = group[1]
      $('.content').empty()
      $('.content').append($('<h1>').append(gname + ' functions'))
      for(i=0; i<functions.length; i++) {
        f = functions[i]
        $('.content').append($('<li>').append(f))
      }
      $('.content').append($('<hr>'))
      for(i=0; i<functions.length; i++) {
        f = functions[i]
        $('.content').append($('<h2>').append(f))
        $('.content').append($('<p>').append(fdata[f]['args']))
        //$('.content').append($('<p>').append(fdata[f]['description']))
        $('.content').append($('<pre>').append(fdata[f]['comments']))
      }
      ws.saveLocation("group/" + gname);
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
      "group/:func":          "group",
      "search/:query":        "search",
    },

    group: function(gname) {
      docurium.showGroup(null, gname)
    },

    search: function(query) {
    }

  });
    
  window.docurium = new Docurium
  window.ws = new Workspace

  docurium.bind('change:version', function(model, version) {
    $('#version').text(version)
  })
  docurium.bind('change:data', function(model, data) {
    model.refreshView()
  })

})
