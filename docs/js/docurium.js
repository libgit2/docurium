$(function() {
  // our document model - stores the datastructure generated from docurium
  var Docurium = Backbone.Model.extend({

    initialize: function() {
      this.set({'version': 'unknown'})
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
      $.get(version + '.json', function(data) {
        docurium.set({'files': data})
      })
    },

  })

  window.docurium = new Docurium

  docurium.bind('change:version', function(model, version) {
    $('#version').text(version)
  })

})
