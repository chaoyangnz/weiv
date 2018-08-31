# Guide for developers

## Component
All the component classes are decorated by `@Component`.

For example:
```js
@Component
class TodoComponent {
  //...
}
```

After decoration:
```text
TodoComponent class
  |- $$                   -> decorated class WeivComponent, which is needed to new a component instance
     |- $$                -> original class: TodoComponent

TodoComponent instance
  |- __id__
  |- __emitter__
  |- __context__
  |- __components__
  |- __plugs__
  |- __root__
  |- __vdom__
  |- __dom__
  |- __proto__
      |- $name
      |- $props
      |- $events
      |- $components
      |- $directives
      |- $ast                  -> AST of compiled(or parsed) template
      |- $emit()
      |- $mount()        
```

## Slot / Plug machanism

Slot / Plug can introduce external rendered pieces into a component template dynamically.

**We ONLY support plugs in its direct children.**
**We DO support a slot for multiple plugs.**

Typical usage:
```js
@Component({
  template: `
  <div>
    <h1>Hello world</h1>
    <slot name="slot2">            <!-- declare slot2 here -->
    <div>
      <p>
        <h3 name="slot1">          <!-- declare slot1 here -->
      </p>
    </div>
  </div>
  `
})
class A {
  // ...
}

@Component({
  template: `
  <div>
    <h1>Will use component A</h1>
    <comp-a>
      <h3 slot="slot1">This is slot2</h3>          <!-- declare a plug for slot1 here -->
      <span slot="slot2"></span>                   <!-- declare a plug for slot2 here -->
    </comp-a>
  </div>
  `,
  components: {
    comp-a: A
  }
})
class B {
  // ...
}
```

The final rendered HTML:
```html
<div>
  <h1>Hello world</h1>
  <span></span>
  <div>
    <p>
      <h3>This is slot2</h3>
    </p>
  </div>
</div>
```

## Scope
Every AST element is associated with a scope and the expression eval for its attributes will first search its own scope, if not found then go upward until the root of AST. In template, there is a special variable `$super` which refers to its upper scope. Most of the time. Scope is the underlying to support some directives, which basically manipulate the scope or other building blocks.

## Directives

Currently directive support is not too stable and it is not easy to extend, but we DO provides commonly used directives:

### `@bind`
The most basic directive to support bind a prop
Usage: `@bind:prop_name="expression"`

Note:
- Here it binds _property_ **NOT** _attribute_
- Content enclosed by double quotes is alway explained to be an expression, so if you want a String literal, use "1 + 'aaa'"
- special property `class`: `@bind:class="{aa: true, bb: false, cc: true}"`, then the final classes is like `class="aa cc"`


### `@on`

This directive is to register event listeners. Typically, this method is used to register custom events emitted through components' `$emit()` method. 
For example: `@on:saveForm="doSave"`, never write `doSave()` which is an illegal expression in this case.
And if you want to use native HTML event attributes to add event listener, two ways can be fine:
- normal way: `<button onclick="doSomething">`
- `@on` directive: `<button @on:click="doSomething">`

### `@for`

Apparently, this directive is to do iteration like `for...in..`

Usage: `@for:item="items"` and you can get special variable `$index` in the scope of the element this directive applies.

### `@if`/`@elif`/`else`
### `@model`
### `@show`
### `@html`
### `@var`
