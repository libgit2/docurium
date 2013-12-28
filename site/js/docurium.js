$(function() {
  var FileListModel = Backbone.Model.extend({
    initialize: function() {
      var docurium = this.get('docurium')
      this.listenTo(docurium, 'change:data', this.extract)
    },

    extract: function() {
      var docurium = this.get('docurium')
      var data = docurium.get('data')

      // Function groups
      var funs = _.map(data['groups'], function(group, i) {
	var name = group[0]
	var link = groupLink(name)
	return {name: name, link: link, num: group[1].length}
      })

      // Types
      var getName = function(type) {
	var name = type[0];
	var link = typeLink(name);
	return {link: link, name: name};
      }

      var enums = _.filter(data['types'], function(type) {
	return type[1]['block'] && type[1]['type'] == 'enum';
      }).map(getName)

      var structs = _.filter(data['types'], function(type) {
	return type[1]['block'] && type[1]['type'] != 'enum'
      }).map(getName)

      var opaques = _.filter(data['types'], function(type) {
	return !type[1]['block']
      }).map(getName)

      // File Listing
      var files = _.map(data['files'], function(file) {
	var url = this.github_file(file['file'])
	return {url: url, name: file['file']}
      }, docurium)

      // Examples List
      var examples = []
      if(data['examples'] && (data['examples'].length > 0)) {
	examples = _.map(data['examples'], function(file) {
	  return {name: file[0], path: file[1]}
	})
      }

      this.set('data', {funs: funs, enums: enums, structs: structs, opaques: opaques,
			files: files, examples: examples})
    },
  })

  var FileListView = Backbone.View.extend({
    el: $('#files-list'),

    template:  _.template($('#file-list-template').html()),

    typeTemplate: _.template($('#type-list-template').html()),

    events: {
      'click h3': 'toggleList',
    },

    toggleList: function(e) {
      $(e.currentTarget).next().toggle(100)
      return false
    },

    initialize: function() {
      this.listenTo(this.model, 'change:data', this.render)
    },

    render: function() {
      var data = this.model.get('data')

      var enumList = this.typeTemplate({title: 'Enums', elements: data.enums})
      var structList = this.typeTemplate({title: 'Structs', elements: data.structs})
      var opaquesList = this.typeTemplate({title: 'Opaque Structs', elements: data.opaques})
      var menu = $(this.template({funs: data.funs, files: data.files, examples: data.examples}))

      $('#types-list', menu).append(enumList, structList, opaquesList)
      $('ul.hidden', menu).hide()

      this.$el.html(menu)
      return this
    },
  })

  var VersionView = Backbone.View.extend({
    el: $('#version'),

    initialize: function() {
      this.listenTo(this.model, 'change:version', this.render)
      this.listenTo(this.model, 'change:name', this.renderName)
      this.title = $('#site-title')
    },

    render: function() {
      var version = this.model.get('version')
      this.$el.text(version)
      this.title.attr('href', '#' + version)
      return this
    },

    renderName: function() {
      var name = this.model.get('name')
      var title = name + ' API'
      this.title.text(title)
      document.title = title
      return this
    },
  })

  var VersionPickerView = Backbone.View.extend({
    el: $('#versions'),

    list: $('#version-list'),

    template: _.template($('#version-picker-template').html()),

    initialize: function() {
      this.listenTo(this.model, 'change:versions', this.render)
    },

    events: {
      'click #version-picker': 'toggleList',
      'click': 'hideList',
    },

    hideList: function() {
      this.list.hide(100)
    },

    toggleList: function(e) {
      $(e.currentTarget).next().toggle(100)
      return false
    },

    render: function() {
      var vers = this.model.get('versions')
      list = this.template({versions: vers})
      this.list.hide().html(list)
      return this
    },
  })

  var ChangelogView = Backbone.View.extend({
    template: _.template($('#changelog-template').html()),

    itemTemplate: _.template($('#changelog-item-template').html()),

    initialize: function() {
      // for every version, show which functions added, removed, changed - from HEAD down
      var versions = this.model.get('versions')
      var sigHist = this.model.get('signatures')

      var lastVer = _.first(versions)

      // fill changelog struct
      var changelog = {}
      for(var i in versions) {
        var version = versions[i]
        changelog[version] = {'deletes': [], 'changes': [], 'adds': []}
      }

      // figure out the adds, deletes and changes
      _.forEach(sigHist, function(func, fname) {
	var lastv = _.last(func.exists)
	var firstv = _.first(func.exists)
	changelog[firstv]['adds'].push(fname)

	// figure out where it was deleted or changed
	if (lastv && (lastv != lastVer)) {
	  var vi = _.indexOf(versions,lastv)
	  var delv = versions[vi-1]
	  changelog[delv]['deletes'].push(fname)

	  _.forEach(func.changes, function(_, v) {
	    changelog[v]['changes'].push(fname)
	  })
	}
      })

      var vers = _.map(versions, function(version) {
	var deletes = changelog[version]['deletes']
	deletes.sort()

	var additions = changelog[version]['adds']
	additions.sort()
	var adds = _.map(additions, function(add) {
          var gname = this.model.groupOf(add)
	  return {link: groupLink(gname, add, version), text: add}
	}, this)

	return {title: version, listing: this.itemTemplate({dels: deletes, adds: adds})}
      }, this)

      this.html = this.template({versions: vers})
    },

    render: function() {
      $('.content').html(this.html)
    }
  })

  var FunctionModel = Backbone.Model.extend({
    initialize: function() {
      var gname = this.get('gname')
      var fname = this.get('fname')
      var docurium = this.get('docurium')

      var group = docurium.getGroup(gname)

      var fdata = docurium.get('data')['functions']
      var functions = group[1]

      // Function Arguments
      var args = _.map(fdata[fname]['args'], function(arg) {
	return {link: this.hotLink(arg.type), name: arg.name, comment: arg.comment}
      }, docurium)

      var data = fdata[fname]
      // function return value
      var ret = data['return']
      var returns = {link: docurium.hotLink(ret.type), comment: ret.comment}
      // function signature
      var sig = docurium.hotLink(ret.type) + ' ' + fname + '(' + data['argline'] + ');'
      // version history
      var sigHist = docurium.get('signatures')[fname]
      var version = docurium.get('version')
      var sigs = _.map(sigHist.exists, function(ver) {
	var klass = []
	if (sigHist.changes[ver])
	  klass.push('changed')
	if (ver == version)
	  klass.push('current')

	return {url: '#' + groupLink(gname, fname, ver), name: ver, klass: klass.join(' ')}
      })
      // GitHub link
      var fileLink = docurium.github_file(data.file, data.line, data.lineto)
      // link to the group
      var alsoGroup = '#' + groupLink(group[0])
      var alsoLinks = _.map(functions, function(f) {
	return {url: '#' + groupLink(gname, f), name: f}
      })

      this.set('data', {name: fname, data: data, args: args, returns: returns, sig: sig,
			sigs: sigs, fileLink: fileLink, groupName: gname,
			alsoGroup: alsoGroup, alsoLinks: alsoLinks})
    }
  })

  var FunctionView = Backbone.View.extend({
    template: _.template($('#function-template').html()),
    argsTemplate: _.template($('#function-args-template').html()),

    render: function() {
      document.body.scrollTop = document.documentElement.scrollTop = 0;
      var data = this.model.get('data')
      data.argsTemplate = this.argsTemplate
      var cont = this.template(data)

      $('.content').html(cont)
      return this
    },
  })

  // our document model - stores the datastructure generated from docurium
  var Docurium = Backbone.Model.extend({

    defaults: {'version': 'unknown'},

    initialize: function() {
      this.loadVersions()
      this.bind('change:version', this.loadDoc)
    },

    loadVersions: function() {
      $.getJSON("project.json").then(function(data) {
        docurium.set({'versions': data.versions, 'github': data.github, 'signatures': data.signatures, 'name': data.name, 'groups': data.groups})
        docurium.setVersion()
      })
    },

    setVersion: function (version) {
      if(!version) {
        version = _.first(docurium.get('versions'))
      }
      docurium.set({version: version})
    },

    loadDoc: function() {
      version = this.get('version')
      $.getJSON(version + '.json').then(function(data) {
        docurium.set({data: data})
      })
    },

    showIndexPage: function(replace) {
      version = docurium.get('version')
      ws.navigate(version, {replace: replace})

      data = docurium.get('data')
      content = $('<div>').addClass('content')
      content.append($('<h1>').append("Public API Functions"))

      sigHist = docurium.get('signatures')

      // Function Group
      data.groups.forEach(function(group) {
        content.append($('<h2>').addClass('funcGroup').append(group[0]))
        list = $('<p>').addClass('functionList')
	links = group[1].map(function(fun) {
          link = $('<a>').attr('href', '#' + groupLink(group[0], fun)).append(fun)
          if(sigHist[fun].changes[version]) {
            link.addClass('changed')
          }
          if(version == _.first(sigHist[fun].exists)) {
            link.addClass('introd')
          }
	  return link
	})

	// intersperse commas between each function
	for(var i = 0; i < links.length - 1; i++) {
	  list.append(links[i])
	  list.append(", ")
	}
	list.append(_.last(links))

	content.append(list)
      })

      $('.content').replaceWith(content)
    },

    getGroup: function(gname) {
      var groups = docurium.get('data')['groups']
      return _.find(groups, function(g) {
	return g[0] == gname
      })
    },

    showType: function(data, manual) {
      var tdata
      var types = this.get('data')['types']
      var tdata = _.find(types, function(g) {
	return g[0] == manual
      })
      tname = tdata[0]
      data = tdata[1]

      ws.navigate(typeLink(tname))
      document.body.scrollTop = document.documentElement.scrollTop = 0;

      content = $('<div>').addClass('content')
      content.append($('<h1>').addClass('funcTitle').append(tname).append($("<small>").append(data.type)))

      content.append($('<p>').append(data.value))

      if(data.comments) {
	content.append($('<div>').append(data.comments))
      }

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
        content.append(flink)
        content.append(', ')
      }

      link = docurium.github_file(data.file, data.line, data.lineto)
      flink = $('<a>').attr('target', 'github').attr('href', link).append(data.file)
      content.append($('<div>').addClass('fileLink').append("Defined in: ").append(flink))

      $('.content').replaceWith(content)
      return false
    },

    showGroup: function(manual, flink) {
      var types = this.get('data')['groups']
      var group = _.find(types, function(g) {
	  return g[0] == manual
      })
      fdata = docurium.get('data')['functions']
      gname = group[0]

      ws.navigate(groupLink(gname));
      document.body.scrollTop = document.documentElement.scrollTop = 0;

      functions = group[1]
      content = $('<div>').addClass('content')
      content.append($('<h1>').append(gname + ' functions'))

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
      content.append(table)

      for(var i=0; i<functions.length; i++) {
        f = functions[i]
        argsText = '( ' + fdata[f]['argline'] + ' )'
        link = $('<a>').attr('href', '#' + groupLink(gname, f)).append(f)
        content.append($('<h2>').append(link).append($('<small>').append(argsText)))
        description = fdata[f]['description']
	if(fdata[f]['comments'])
		description += "\n\n" + fdata[f]['comments']

	content.append($('<div>').addClass('description').append(description))
      }

      $('.content').replaceWith(content)
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
        var link = $('<a>').attr('href', '#' + typeLink(typeName)).append(typeName)[0]
        text = text.replace(re, link.outerHTML + ' ')
      }
      return text
    },

    groupOf: function (func) {
      return this.get('groups')[func]
    },

    github_file: function(file, line, lineto) {
      var data = this.get('data')
      url = ['https://github.com', docurium.get('github'),
	     'blob', docurium.get('version'), data.prefix, file].join('/')
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
      var value = $('#search-field').val()

      if (value.length < 3) {
        docurium.showIndexPage(false)
        return
      }

      this.searchResults = []

      ws.navigate(searchLink(value))

      data = docurium.get('data')

      // look for functions (name, comment, argline)
      _.forEach(data.functions, function(f, name) {
	gname = docurium.groupOf(name)
	// look in the function name first
        if (name.search(value) > -1) {
          var flink = $('<a>').attr('href', '#' + groupLink(gname, name)).append(name)
	  searchResults.push({link: flink, match: 'function', navigate: groupLink(gname, name)})
	  return
        }

	// if we didn't find it there, let's look in the argline
        if (f.argline && f.argline.search(value) > -1) {
          var flink = $('<a>').attr('href', '#' + groupLink(gname, name)).append(name)
          searchResults.push({link: flink, match: f.argline, navigate: groupLink(gname, name)})
        }
      })

      // look for types
      data.types.forEach(function(type) {
        name = type[0]
        if (name.search(value) > -1) {
          var link = $('<a>').attr('href', '#' + typeLink(name)).append(name)
          searchResults.push({link: link, match: type[1].type, navigate: typeLink(name)})
        }
      })

      // if we have a single result, show that page
      if (searchResults.length == 1) {
         ws.navigate(searchResults[0].navigate, {trigger: true, replace: true})
         return
      }

      content = $('<div>').addClass('content')
      content.append($('<h1>').append("Search Results"))
      rows = _.map(searchResults, function(result) {
	return $('<tr>').append(
	  $('<td>').append(result.link),
	  $('<td>').append(result.match))
      })

      content.append($('<table>').append(rows))
      $('.content').replaceWith(content)
    }

  })

  var Workspace = Backbone.Router.extend({

    routes: {
      "":                             "main",
      ":version":                     "main",
      ":version/group/:group":        "group",
      ":version/type/:type":          "showtype",
      ":version/group/:group/:func":  "groupFun",
      ":version/search/:query":       "search",
      "p/changelog":                  "changelog",
    },

    main: function(version) {
      docurium.setVersion(version)
      // when asking for '/', replace with 'HEAD' instead of redirecting
      var replace = version == undefined
      docurium.showIndexPage(replace)
    },

    group: function(version, gname) {
      docurium.setVersion(version)
      docurium.showGroup(gname)
    },

    groupFun: function(version, gname, fname) {
      docurium.setVersion(version)
      var model = new FunctionModel({docurium: docurium, gname: gname, fname: fname})
      var view = new FunctionView({model: model})
      if (this.currentView)
	this.currentview.remove()

      this.currentview = view
      view.render()
    },

    showtype: function(version, tname) {
      docurium.setVersion(version)
      docurium.showType(null, tname)
    },

    search: function(version, query) {
      docurium.setVersion(version)
      $('#search-field').val(query)
      docurium.search()
    },

    changelog: function(version, tname) {
      // let's wait to process it until it's asked, and let's only do
      // it once
      if (this.changelogView == undefined) {
	this.changelogView = new ChangelogView({model: docurium})
      }
      docurium.setVersion()
      this.changelogView.render()
    },

  });

  function groupLink(gname, fname, version) {
    if(!version) {
      version = docurium.get('version')
    }
    if(fname) {
      return version + "/group/" + gname + '/' + fname
    } else {
      return version + "/group/" + gname
    }
  }

  function typeLink(tname) {
    return docurium.get('version') + "/type/" + tname
  }

  function searchLink(tname) {
    return docurium.get('version') + "/search/" + tname
  }

  //_.templateSettings.variable = 'rc'

  window.docurium = new Docurium
  window.ws = new Workspace
  docurium.once('change:data', function() {Backbone.history.start()})

  var fileList = new FileListModel({docurium: window.docurium})
  var fileListView = new FileListView({model: fileList})
  var versionView = new VersionView({model: window.docurium})
  var versionPickerView = new VersionPickerView({model: window.docurium})

  $('#search-field').keyup( docurium.search )
})
