import debug from 'debug'
import {
  BindDirective, OnDirective, IfDirective, ElifDirective, ElseDirective, VarDirective,
  ForDirective, ShowDirective, HtmlDirective, ModelDirective
} from './directive'

export { Component } from './component'
export { Directive } from './directive'
export { observable, action, computed } from 'mobx'

// global registry
const $components = new Map()
const $directives = new Map()

export function component(tag: string, componentClass: any) {
  if (!componentClass) return $components.get(tag)

  if ($components.has(tag)) {
    console.log('Component has been registered: %s', tag)
  }
  $components.set(tag, componentClass.$$)
}

export function directive(name: string, directive: any) {
  if (!directive) return $directives.get(name)
  if ($directives.has(name)) {
    console.log('Directive has been registered: %s', name)
  }
  $directives.set(name, directive)
}

// set all debug to console.debug
debug.log = console.log.bind(console)

// register built-in directives
directive('var', VarDirective)
directive('bind', BindDirective)
directive('on', OnDirective)
directive('if', IfDirective)
directive('elif', ElifDirective)
directive('else', ElseDirective)
directive('for', ForDirective)
directive('show', ShowDirective)
directive('html', HtmlDirective)
directive('model', ModelDirective)
