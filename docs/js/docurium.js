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
        }
      })
    },

    collapseSection: function(data) {
      $(this).next().toggle(100)
    },

    loadFile: function(data) {
      console.log($(this))
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
      _.each(data['groups'], function(group) {
        flink = $('<a href="#">' + group[0] + ' &nbsp;<small>(' + group[1].length + ')</small></a>')
        //flink.click( this.loadFile )
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

  var DocFile = Backbone.Model.extend({
  })

  var DocFileGroup = Backbone.Collection.extend({
    model: DocFile
  })

  window.docurium = new Docurium

  // gonna wanna do this in docuriumview, i think
  docurium.bind('change:version', function(model, version) {
    $('#version').text(version)
  })
  docurium.bind('change:data', function(model, data) {
    model.refreshView()
  })

})
