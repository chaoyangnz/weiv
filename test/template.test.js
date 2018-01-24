import { parse } from 'template'

console.debug = console.log

it('compile template', () => {
  const ast = parse('<template />')
  console.log(ast)
  console.log(ast.render())
  expect(ast.tagName === 'DIV').toBe(false)
})
