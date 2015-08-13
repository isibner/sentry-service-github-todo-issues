{parseTodos} = require '../src/todoUtils'
[fs, path, {assert}, _] = ['fs', 'path', 'chai', 'lodash'].map require

fixturesDir = path.join __dirname, 'fixtures'

checkTodosMatch = (expected, actual) ->
  assert.lengthOf actual, expected.length
  for i in [0..expected.length - 1]
    for key, val of expected[i]
      assert.deepEqual actual[i][key], expected[i][key]

describe 'todoUtils.parseTodos', ->
  it 'should parse Java with block comments', (done) ->
    files = [path.join(fixturesDir, 'BlockComments.java')]
    expected = JSON.parse fs.readFileSync(path.join(fixturesDir, 'BlockComments.java.json'), 'utf8')
    parseTodos files, fixturesDir, (err, todos) ->
      done(err) if err?
      flatTodos = _.flatten(todos)
      checkTodosMatch(expected, flatTodos)
      done()

  it 'should parse Python with multiple comments', (done) ->
    files = [path.join(fixturesDir, 'MultipleComments.py')]
    expected = JSON.parse fs.readFileSync(path.join(fixturesDir, 'MultipleComments.py.json'), 'utf8')
    parseTodos files, fixturesDir, (err, todos) ->
      done(err) if err?
      flatTodos = _.flatten(todos)
      checkTodosMatch(expected, flatTodos)
      done()

it 'should parse Java with mixed comments', (done) ->
    files = [path.join(fixturesDir, 'Foo2.java')]
    expected = JSON.parse fs.readFileSync(path.join(fixturesDir, 'Foo2.java.json'), 'utf8')
    parseTodos files, fixturesDir, (err, todos) ->
      done(err) if err?
      flatTodos = _.flatten(todos)
      checkTodosMatch(expected, flatTodos)
      done()
