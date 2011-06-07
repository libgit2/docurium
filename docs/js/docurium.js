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
      console.log($(this))
      $(this).toggleClass('disable')
      $(this).next().toggle(100)
    },

    loadFile: function(data) {
      console.log(this)
    },

    refreshView: function() {
      data = this.get('data')

      // File Listing
      files = $('<li>')
      title = $('<h3 class="disable"><a href="#">Files</a></h3>').click( this.collapseSection )
      files.append(title)
      filelist = $('<ul>')
      _.each(data['files'], function(file, i, data) {
        flink = $('<a href="#">' + file['file'] + '</a>')
        flink.click( this.loadFile )
        fitem = $('<li>')
        fitem.append(flink)
        filelist.append(fitem)
      }, this)
      files.append(filelist)

      list = $('#files-list')
      list.empty()
      list.append(files)
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
