{getChangesFor} = require '../src/todoUtils'
[fs, path, {assert}, _] = ['fs', 'path', 'chai', 'lodash'].map require

fixturesDir = path.join __dirname, 'fixtures'

checkTodosMatch = (expected, actual) ->
  assert.lengthOf actual, expected.length
  for i in [0..expected.length - 1]
    for key, val of expected[i]
      assert.deepEqual actual[i][key], expected[i][key]

describe 'todoUtils.getChangesFor', ->
  it 'should register a change when only the description changes', ->
    oldTodos = JSON.parse fs.readFileSync(path.join(fixturesDir, 'only-description/old.json'), 'utf8')
    newTodos = JSON.parse fs.readFileSync(path.join(fixturesDir, 'only-description/new.json'), 'utf8')
    assert.strictEqual oldTodos[0].issueNumber, 1
    expected =
      changed: [_.extend(newTodos[0], {issueNumber: 1})]
      added: []
      deleted: []
      unchanged: []
    assert.deepEqual getChangesFor(oldTodos, newTodos), expected

  it 'should register as a change when the title changes', ->
    oldTodos = JSON.parse fs.readFileSync(path.join(fixturesDir, 'only-title/old.json'), 'utf8')
    newTodos = JSON.parse fs.readFileSync(path.join(fixturesDir, 'only-title/new.json'), 'utf8')
    assert.strictEqual oldTodos[0].issueNumber, 1
    expected =
      changed: [_.extend(newTodos[0], {issueNumber: 1})]
      added: []
      deleted: []
      unchanged: []
    assert.deepEqual getChangesFor(oldTodos, newTodos), expected

  it 'should register as a change when the labels change', ->
    oldTodos = JSON.parse fs.readFileSync(path.join(fixturesDir, 'only-labels/old.json'), 'utf8')
    newTodos = JSON.parse fs.readFileSync(path.join(fixturesDir, 'only-labels/new.json'), 'utf8')
    assert.strictEqual oldTodos[0].issueNumber, 1
    expected =
      changed: [_.extend(newTodos[0], {issueNumber: 1})]
      added: []
      deleted: []
      unchanged: []
    assert.deepEqual getChangesFor(oldTodos, newTodos), expected

  it 'should register as a change when the line numbers change', ->
    oldTodos = JSON.parse fs.readFileSync(path.join(fixturesDir, 'only-linenum/old.json'), 'utf8')
    newTodos = JSON.parse fs.readFileSync(path.join(fixturesDir, 'only-linenum/new.json'), 'utf8')
    assert.strictEqual oldTodos[0].issueNumber, 1
    expected =
      changed: [_.extend(newTodos[0], {issueNumber: 1})]
      added: []
      deleted: []
      unchanged: []
    assert.deepEqual getChangesFor(oldTodos, newTodos), expected

  it 'should register when a todo is added', ->
    oldTodos = JSON.parse fs.readFileSync(path.join(fixturesDir, 'add-todo/old.json'), 'utf8')
    newTodos = JSON.parse fs.readFileSync(path.join(fixturesDir, 'add-todo/new.json'), 'utf8')
    assert.strictEqual oldTodos[0].issueNumber, 1
    expected =
      changed: []
      added: [newTodos[1]]
      deleted: []
      unchanged: [oldTodos[0]]
    assert.deepEqual getChangesFor(oldTodos, newTodos), expected

  it 'should register when a todo is deleted', ->
    oldTodos = JSON.parse fs.readFileSync(path.join(fixturesDir, 'remove-todo/old.json'), 'utf8')
    newTodos = JSON.parse fs.readFileSync(path.join(fixturesDir, 'remove-todo/new.json'), 'utf8')
    assert.strictEqual oldTodos[0].issueNumber, 1
    expected =
      changed: []
      added: []
      deleted: [oldTodos[1]]
      unchanged: [oldTodos[0]]
    assert.deepEqual getChangesFor(oldTodos, newTodos), expected
