import jexl from 'jexl-sync'

it('jexl', () => {
  var context = {
    ab: true
  }
  const value = jexl.eval('{atodo: ab }', context)
  expect(value !== undefined)
  console.log(value)
})

it('identifier contains $', () => {
  const value = jexl.eval('$a', {$a: 1})
  console.log(value)
})

it('parse || ', () => {
  const ast = jexl.parse('text || value')
  console.log(ast)
})
