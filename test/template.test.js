import { compile } from 'template'

console.debug = console.log

it('compile template', () => {
  const ast = compile('<div></div>')
  expect(ast.tagName === 'DIV').toBe(false)
})
