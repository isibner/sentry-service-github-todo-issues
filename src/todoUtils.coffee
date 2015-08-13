_ = require 'lodash'
isTextOrBinary = require 'istextorbinary'
path = require 'path'
child_process = require 'child_process'
async = require 'async'
fs = require 'fs'
diff = require('deep-diff').diff

defaultRegexes =
  todoRegex: /^[\+|\-]?[\s]*[\W]*[\s]*TODO[\W|\s]*(?=\w+)/i
  labelRegex: /^\+?[\s]*[\W]*[\s]*LABELS[\W|\s]*(?=\w+)/i
  bodyRegex: /^\+?[\s]*[\W]*[\s]*BODY[\W|\s]*(?=\w+)/i
  extensions: []

fileRegexes = [
  {
    todoRegex: /^[\+|\-]?[\s]*[\/\/|\*][\s]*TODO[\W|\s]*(?=\w+)/i,
    labelRegex: /^\+?[\s]*[\/\/|\*][\s]*LABELS[\W|\s]*(?=\w+)/i,
    bodyRegex: /^\+?[\s]*[\/\/|\*][\s]*(?=\w+)/i,
    extensions: [ '.c', '.cpp', '.java', '.js', '.less', '.m', '.sass', '.scala', '.scss', '.swift']
  },
  {
    todoRegex: /^[\+|\-]?[\s]*[#]+[\s]*TODO[\W|\s]*(?=\w+)/i,
    labelRegex: /^\+?[\s]*[#]+[\s]*LABELS[\W|\s]*(?=\w+)/i,
    bodyRegex: /^\+?[\s]*[#]+[\W|\s]*(?=\w+)/i,
    extensions: ['.bash', '.coffee', '.pl', '.py', '.rb', '.sh', '.zsh']
  }
]

trim = (str) -> str.trim()

getExtension = (filename) -> if filename.lastIndexOf('.') >= 0 then filename.substring(filename.lastIndexOf('.')) else null

regexesForFilename = (filename) ->
  extension = getExtension(filename)
  unless extension is null
    for fileRegex in fileRegexes
      return fileRegex if fileRegex.extensions.indexOf(extension) >= 0
  return defaultRegexes

isTodo = (line, filename) ->
  regexes = regexesForFilename(filename)
  return regexes.todoRegex.test(line)

getTodoTitle = (line, filename) ->
  regexes = regexesForFilename(filename)
  return line.split(regexes.todoRegex)[1]

isTodoLabel = (line, filename) ->
  regexes = regexesForFilename(filename)
  return regexes.labelRegex.test(line)

getTodoLabels = (line, filename) ->
  regexes = regexesForFilename(filename)
  rawLabels = line.split(regexes.labelRegex)[1].split(',')
  return _(rawLabels).map(trim).uniq().value()

isTodoBody = (line, filename) ->
  regexes = regexesForFilename(filename)
  return regexes.bodyRegex.test(line)

getTodoBody = (line, filename) ->
  regexes = regexesForFilename(filename)
  return line.split(regexes.bodyRegex)[1]

blameDataFromLines = (lines, tempPath, relativeFilename, callback) ->
  mapIterator = ({line, lineNumFrom0}, lineCb) ->
    if line is '' and lineNumFrom0 is lines.length - 1
      return lineCb(null, {line, lineNumFrom0, committerName: null, commitSha: null})
    child_process.exec "git blame -l -L #{lineNumFrom0 + 1},+1 -- #{relativeFilename}", {cwd: tempPath}, (err, stdout) ->
      lineCb(err) if err
      importantPart = stdout.substring(0, stdout.indexOf(')') + 1)
      commitSha = importantPart.split('(')[0].trim()
      committerName = importantPart.split('(')[1].split(/[\d]{4}\-[\d]{2}\-[\d]{2}/i)[0].trim()
      lineCb(null, {line, lineNumFrom0, committerName, commitSha})
  async.mapLimit lines, 10, mapIterator, callback

parseTodos = (files, tempPath, callback) ->
  textFiles = files.filter (file) ->
    return isTextOrBinary.isTextSync file, fs.readFileSync(file)
  mapIterator = (filename, cb) ->
    todosForFile = []
    relativeFilename = path.relative(tempPath, filename)
    lines = _.map fs.readFileSync(filename, 'utf8').split('\n'), (line, lineNumFrom0) -> {line, lineNumFrom0}
    blameDataFromLines lines, tempPath, relativeFilename, (err, lineData) ->
      cb(err) if err?
      for datum in lineData
        {line, lineNumFrom0, committerName, commitSha} = datum
        if isTodo line, relativeFilename
          parsingTodo = true
          todosForFile.push {
            lineNum: lineNumFrom0 + 1
            path: relativeFilename
            shas: [commitSha]
            committers: [committerName]
            labels: ['todo']
            body: null
            title: getTodoTitle(line, relativeFilename)
          }
        else if parsingTodo
          lastTodo = todosForFile[todosForFile.length - 1]
          if isTodoLabel(line, relativeFilename)
            lastTodo.labels = lastTodo.labels.concat getTodoLabels(line, relativeFilename)
            unless _.contains lastTodo.shas, commitSha
              lastTodo.shas.push commitSha
              lastTodo.committers.push committerName
          else if isTodoBody(line, relativeFilename)
            lastTodo.body ?= ''
            todoLineBody = getTodoBody(line, relativeFilename)
            if todoLineBody?
              lastTodo.body += ' ' + getTodoBody(line, relativeFilename).trim()
              lastTodo.body = lastTodo.body.trim()
              unless _.contains lastTodo.shas, commitSha
                lastTodo.shas.push commitSha
                lastTodo.committers.push committerName
          else
            parsingTodo = false
      cb(null, todosForFile)

  async.mapLimit textFiles, 10, mapIterator, callback

getChangesFor = (originalTodos, newTodos) ->
  originalTodos = _.sortByAll originalTodos, ['path', 'lineNum']
  newTodos = _.sortByAll newTodos, ['path', 'lineNum']
  changed = []
  added = []
  deleted = []
  for diffObject in diff(originalTodos, newTodos)
    {kind, index, item, path:keyList, lhs, rhs} = diffObject
    switch kind
      when 'E'
        # keyList should be of length 2
        [idx, key] = keyList
        if key in ['body', 'title', 'lineNum']
          changed.push _.extend(newTodos[idx], {issueNumber: originalTodos[idx].issueNumber})
      when 'A'
        if index? and not keyList?
          {kind, lhs, rhs} = item
          switch kind
            when 'N'
              added.push rhs
            when 'D'
              deleted.push lhs
        else
          [idx, key] = keyList
          if key in ['shas', 'committers', 'labels']
            changed.push _.extend(newTodos[idx], {issueNumber: originalTodos[idx].issueNumber})
  unchanged = _.filter originalTodos, ({issueNumber}) ->
    not _.findWhere(changed, {issueNumber})? and not _.findWhere(deleted, {issueNumber})?
  return _.mapValues {changed, unchanged, added, deleted}, _.uniq

module.exports = {getExtension, isTodo, getTodoTitle, isTodoLabel, getTodoLabels,
  isTodoBody, getTodoBody, parseTodos, getChangesFor}
