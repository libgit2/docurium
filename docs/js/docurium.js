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
          fs = _.map(data, function(val, key) {
            return new DocFile({file: key, functions: val['functions'], meta: val['meta']})
          })
          files.refresh(fs)
        }
      })
    },
  })

  var DocFile = Backbone.Model.extend({
  })

  var DocFileGroup = Backbone.Collection.extend({
    model: DocFile
  })


  var DocFileView = Backbone.View.extend({
    tagName: "li",
    className: "file-entry",

    initialize: function() {
      _.bindAll(this, "render")
    },

    render: function() {
      $(this.el).html("<h3><a>" + this.model.get('file') + "</a></h3>"); 
      return this
    }
  })

  var DocFileGroupView = Backbone.View.extend({
    tagName: "li",
    className: "file-group",

    initialize: function() {
      _.bindAll(this, "render")
      this.collection.bind('all',     this.render);
    },

    render: function() {
      $("#files-list").empty()
      _.each(this.collection.models, function(doc) {
        console.log(doc)
        var view = new DocFileView({model: doc})
        $("#files-list").append(view.render().el)
      })
      return this
    }
  })

  var DocuriumView = Backbone.View.extend({
  })
    
  window.docurium = new Docurium
  window.files = new DocFileGroup

  // gonna wanna do this in docuriumview, i think
  docurium.bind('change:version', function(model, version) {
    $('#version').text(version)
  })

  window.App = new DocFileGroupView({collection: files})

})
