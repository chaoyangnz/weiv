import {observable} from 'mobx'

class A {
  @observable
  a = 9
}

it('xx', () => {
  console.log(Object.getPrototypeOf(new A()))
})
