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

    refreshView: function() {
      data = this.get('data')
      list = $('#files-list')
      list.empty()
      _.each(data['files'], function(file) {
        list.append($('<h3>' + file + '</h3>'))
      }
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
