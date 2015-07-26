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

CONSTANTS = {
  NAME: 'github-todo-issues'
  DISPLAY_NAME: 'Todo Tracker for Github Issues'
  ICON_FILE_PATH: path.join(__dirname, '../', '123.png')
  AUTH_ENDPOINT: null
}

class GithubIssuesTodoService
  constructor: ({@config, @packages, @db, @sourceProviders}) ->
    {github: {@CLIENT_ID, @CLIENT_SECRET, @BOT_USERNAME, @BOT_PASSWORD, @USER_AGENT}} = @config
    {mongoose, 'mongoose-findorcreate': findOrCreate} = @packages
    GithubTodoIssuesSchema = new mongoose.Schema {
      repoId: {type: String, required: true},
      userId: {type: String, required: true},
      sourceProviderName: {type: String, required: true},
      todos: mongoose.Schema.Types.Mixed
    }
    GithubTodoIssuesSchema.plugin findOrCreate
    @GithubTodoIssuesModel = mongoose.model 'github-todo-issues:GithubTodoIssuesModel', GithubTodoIssuesSchema
    _.extend @, CONSTANTS

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
    todos = []
    @GithubTodoIssuesModel.findOne {repoId, userId, sourceProviderName}, (err, model) =>
      callback(err) if err?
      todoUtils.parseTodos files, tempPath, (err, mappedTodos) =>
        callback(err) if err?
        child_process.exec 'git rev-parse HEAD', {cwd: tempPath}, (err, latestSha) ->
          callback(err) if err?
          allTodos = _.flatten mappedTodos
          githubAPI = github.botAuth(@BOT_USERNAME, @BOT_PASSWORD, @USER_AGENT)
          mapCreateTodoIssue = (todo, cb) ->
            [user, repo] = repoModel.repoId.split('/')
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
    todos = []
    @GithubTodoIssuesModel.findOne {repoId, userId, sourceProviderName}, (err, model) =>
      callback(err) if err
      todoUtils.parseTodos files, tempPath, (err, mappedTodos) =>
        callback(err) if err
        allTodos = _.flatten mappedTodos
        githubAPI = github.botAuth(@BOT_USERNAME, @BOT_PASSWORD, @USER_AGENT)
        {changed, added, deleted} = todoUtils.getChangesFor(model.todos, allTodos)
        callback()


  deactivateServiceForRepo: (repoModel, callback) ->
    {repoId, userId, sourceProviderName} = repoModel
    @GithubTodoIssuesModel.findOneAndRemove {repoId, userId, sourceProviderName}, (err) =>
      return callback(err) if err
      callback(null, "#{@DISPLAY_NAME} removed successfully.")

module.exports = GithubIssuesTodoService

