import { parse } from 'template'

console.debug = console.log

it('compile template', () => {
  const ast = parse('<div></div>')
  expect(ast.tagName === 'DIV').toBe(false)
})
