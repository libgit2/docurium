$(function() {
  // our document model - stores the datastructure generated from docurium
  var Docurium = Backbone.Model.extend({
    initialize: function() {
      if (!this.get("version")) {
        this.set({"version": "unknown"})
      }
    }
  })

  window.docurium = new Docurium;

  docurium.bind('change:version', function(model, version) {
    $('#version').text(version)
  });


  $.get("versions.json", function(data) {
    docurium.set({'version': 'HEAD'})
    console.log(data)
  })

})
