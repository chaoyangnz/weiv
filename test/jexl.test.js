import jexl from 'jexl-sync'

it('jexl', () => {
  var context = {
    a1: true
  }
  const value = jexl.eval('{atodo: a1}', context)
  expect(value !== undefined)
  console.log(value)
})
