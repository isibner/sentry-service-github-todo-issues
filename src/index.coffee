_ = require 'lodash'
Handlebars = require 'handlebars'
path = require 'path'
url = require 'url'
fs = require 'fs'
querystring = require 'querystring'
isTextOrBinary = require 'istextorbinary'
todoUtils = require './todoUtils'
github = require './github'
async = require 'async'
child_process = require 'child_process'

class GithubIssuesTodoService
  @NAME: 'github-todo-issues'
  @DISPLAY_NAME: 'Todo Tracker for Github Issues'
  @ICON_FILE_PATH: path.join(__dirname, '../', '123.png')
  @AUTH_ENDPOINT: null
  @WORKS_WITH_SOURCES: ['github', 'github-private']

  constructor: ({@config, @packages, @db, @sourceProviders}) ->
    {mongoose, 'mongoose-findorcreate': findOrCreate} = @packages
    GithubTodoIssuesSchema = new mongoose.Schema {
      repoId: {type: String, required: true},
      userId: {type: String, required: true},
      sourceProviderName: {type: String, required: true},
      todos: mongoose.Schema.Types.Mixed
    }
    GithubTodoIssuesSchema.plugin findOrCreate
    @GithubTodoIssuesModel = mongoose.model 'github-todo-issues:GithubTodoIssuesModel', GithubTodoIssuesSchema

  isAuthenticated: (req) ->
    return req.user?.pluginData?.github?

  initializeAuthEndpoints: (router) ->

  initializeOtherEndpoints: (router) ->

  activateServiceForRepo: (repoModel, callback) ->
    {repoId, userId, sourceProviderName} = repoModel
    @GithubTodoIssuesModel.findOrCreate {repoId, userId, sourceProviderName}, (err, model, created) =>
      return callback(err) if err
      successMessage = "Todo issue tracking activated!"
      if not created
        model.todos = []
        model.markModified 'todos'
        model.save (err) ->
          callback(err, successMessage)
      else
        callback(null, successMessage)

  handleInitialRepoData: (repoModel, {files, tempPath}, callback) ->
    {repoId, userId, sourceProviderName} = repoModel
    sourceProvider = _.findWhere @sourceProviders, {NAME: sourceProviderName}
    {BOT_USERNAME, BOT_PASSWORD, USER_AGENT} = sourceProvider.config
    async.parallel [
      ((cb) => @GithubTodoIssuesModel.findOne {repoId, userId, sourceProviderName}, cb)
      ((cb) -> todoUtils.parseTodos files, tempPath, cb)
      ((cb) -> child_process.exec 'git rev-parse HEAD', {cwd: tempPath}, cb)
    ], (err, [model, mappedTodos, latestSha]) =>
      callback(err) if err?
      allTodos = _.flatten mappedTodos
      githubAPI = github.botAuth(BOT_USERNAME, BOT_PASSWORD, USER_AGENT)
      [user, repo] = repoModel.repoId.split('/')
      mapCreateTodoIssue = (todo, cb) ->
        githubAPI.createTodoIssue {todo, user, repo, latestSha}, (err, issueNumber) ->
          cb(err) if err
          todo.issueNumber = issueNumber
          cb(null, todo)
      async.mapSeries allTodos, mapCreateTodoIssue, (err, todos) ->
        callback(err) if err
        model.todos = todos
        model.markModified 'todos'
        model.save(callback)

  handleHookRepoData: (repoModel, {files, tempPath}, callback) ->
    {repoId, userId, sourceProviderName} = repoModel
    sourceProvider = _.findWhere @sourceProviders, {NAME: sourceProviderName}
    {BOT_USERNAME, BOT_PASSWORD, USER_AGENT} = sourceProvider.config
    async.parallel [
      ((cb) => @GithubTodoIssuesModel.findOne {repoId, userId, sourceProviderName}, cb)
      ((cb) -> todoUtils.parseTodos files, tempPath, cb)
      ((cb) -> child_process.exec 'git rev-parse HEAD', {cwd: tempPath}, cb)
    ], (err, [model, mappedTodos, latestSha]) =>
      callback(err) if err?
      allTodos = _.flatten mappedTodos
      githubAPI = github.botAuth(BOT_USERNAME, BOT_PASSWORD, USER_AGENT)
      {changed, added, deleted, unchanged} = todoUtils.getChangesFor(model.todos, allTodos)
      [user, repo] = repoModel.repoId.split('/')
      mapChangedUnchangedIssue = (todo, changeCallback) ->
        githubAPI.updateTodoIssue {todo, user, repo, latestSha}, changeCallback
      mapDeletedIssue = (todo, deleteCallback) ->
        githubAPI.deleteTodoIssue {todo, user, repo}, deleteCallback
      # TODO - Filter this out since it's used twice and nontrivial
      mapCreateTodoIssue = (todo, createCallback) ->
        githubAPI.createTodoIssue {todo, user, repo, latestSha}, (err, issueNumber) ->
          cb(err) if err
          todo.issueNumber = issueNumber
          cb(null, todo)
      async.parallel [
        ((cb) -> async.mapSeries added, mapCreateTodoIssue, cb)
        ((cb) -> async.eachSeries changed, mapChangedUnchangedIssue, cb)
        ((cb) -> async.eachSeries unchanged, mapChangedUnchangedIssue, cb)
        ((cb) -> async.eachSeries deleted, mapDeletedIssue, cb)
      ], (err, results) ->
        callback(err) if err?
        addedWithIssueNumbers = results[0]
        todos = changed.concat(unchanged).concat(addedWithIssueNumbers)
        model.todos = todos
        model.markModified 'todos'
        model.save(callback)

  deactivateServiceForRepo: (repoModel, callback) ->
    {repoId, userId, sourceProviderName} = repoModel
    @GithubTodoIssuesModel.findOneAndRemove {repoId, userId, sourceProviderName}, (err) =>
      return callback(err) if err
      callback(null, "#{@DISPLAY_NAME} removed successfully.")

module.exports = GithubIssuesTodoService

