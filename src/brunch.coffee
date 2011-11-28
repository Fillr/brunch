fs = require 'fs'
path = require 'path'
fileUtil = require 'file' 

compilers = require './compilers'
helpers = require './helpers'
testrunner = require './testrunner'


exports.VERSION = require('./package').version

exports.Brunch = class Brunch
  defaultConfig:
    appPath: './'
    dependencies: []
    minify: no
    mvc: 'backbone'
    templates: 'eco'
    styles: 'css'
    tests: 'jasmine'
    templateExtension: 'eco'  # Temporary.

  constructor: (options) ->
    options = helpers.extend @defaultConfig, options
    options.buildPath ?= path.join options.appPath, 'build/'
    # Nomnom arg parser creates properties in options for internal use
    # We don't need them.
    ignored = ['_'].concat [0..10]
    for prop in ignored when prop of options
      delete options[prop]
    @options = options
    @compilers = (new compiler @options for name, compiler of compilers)
    @watcher = new helpers.Watcher

  _makeCallback: (fn) ->
    => fn? this

  _compile: (compilers, callback) ->
    total = compilers.length
    for compiler in compilers
      do (compiler) =>
        compiler.compile ['.'], =>
          # Pop current compiler from queue.
          total -= 1
          # Execute callbacks if compiler queue is empty.
          callback() unless total

  new: (callback) ->
    callback = @_makeCallback callback
    templatePath = path.join module.id, '/../../template/base'
    path.exists @options.appPath, (exists) =>
      if exists
        helpers.logError '[Brunch]: can\'t create project;
        directory already exists'
        return

      fileUtil.mkdirsSync @options.appPath, 0755
      fileUtil.mkdirsSync @options.buildPath, 0755

      helpers.recursiveCopy templatePath, @options.appPath, =>
        helpers.log '[Brunch]: created brunch directory layout'
        callback()
    this

  build: (callback) ->
    callback = @_makeCallback callback
    helpers.createBuildDirectories @options.buildPath
    @_compile @compilers, callback
    from = path.join @options.appPath, 'src', 'app', 'assets', 'index.html'
    to = path.join @options.buildPath, 'index.html'
    helpers.copyFile from, to
    this

  watch: (callback) ->
    callback = @_makeCallback callback
    helpers.createBuildDirectories @options.buildPath
    sourcePath = path.join @options.appPath, 'src'
    timer = null

    @watcher.add(sourcePath).onChange (file) =>
      for compiler in @compilers when compiler.matchesFile file
        return compiler.onFileChanged file, =>
          clearTimeout timer if timer
          timer = setTimeout callback, 20
    this

  stopWatching: (callback) ->
    @watcher.clear()

  test: (callback) ->
    callback = @_makeCallback callback
    testrunner.run @options, callback

  generate: (callback) ->
    callback = @_makeCallback callback
    extension = switch @options.generator
      when 'style' then 'styl'
      when 'template' then 'eco'
      else 'coffee'
    filename = "#{@options.name}.#{extension}"
    filePath = path.join @options.appPath, 'src', 'app',
      "#{@options.generator}s", filename
    data = switch extension
      when 'coffee'
        className = helpers.formatClassName @options.name
        genName = helpers.capitalize @options.generator
        "class exports.#{className} extends Backbone.#{genName}\n"
      else ''

    fs.writeFile filePath, data, (error) ->
      return helpers.logError error if error?
      helpers.log "Generated #{filePath}"
    this


for method in ['new', 'build', 'watch', 'test', 'generate']
  do (method) ->
    exports[method] = (options, callback) ->
      (new Brunch options)[method] callback
