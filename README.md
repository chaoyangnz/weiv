## What is `weiv`

weiv.js - A home-brew UI view library for modern component-based web development.
`Weiv` is the reverse of the word `View`.

## Why `weiv`?

This is an era of evolution with tons of front-end frameworks: React, Angular, Vue, Preact, Ractive, Svelte. Probably like me, you also feel tired to follow this one or another one. So I choose to reinvent the wheel and eat my own dog food.

## How it's like

```javascript
@Component({
  target: '#app',
  template: `
  <div>
    <h1>{{firstName}} {{lastName}}</h1><p>{{blogURL}}</p>
    {{#manager}}Manager: {{firstName}} {{lastName}}{{/manager}}
  </div>
  `
})
export class App {
  firstName = 'Christophe'
  lastName = 'Coenraets'
  blogURL = 'http://yangchao'
  manager = {
    firstName: 'Chao',
    lastName: 'Yang'
  }
}

Weiv.mount(new App())

Weiv.startup()
```

## Building blocks & Credits

- [virtual dom](https://github.com/Matt-Esch/virtual-dom)
- [Hogan](https://github.com/twitter/hogan.js/)
- [mustache](https://github.com/janl/mustache.js)
- [mobx](https://github.com/mobxjs/mobx)
- [html-to-vdom](https://github.com/TimBeyer/html-to-vdom) 
