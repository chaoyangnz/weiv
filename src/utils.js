export function log(collapsed = false) {
  return function logDecorator(target, name, descriptor) {
    const original = descriptor.value;
    if (typeof original === 'function') {
      descriptor.value = function (...args) {
        if (collapsed) {
          console.groupCollapsed(this)
        } else {
          console.group(this)
        }
        // console.group(`Arguments: ${args}`);
        try {
          const result = original.apply(this, args);
          // console.log(`Result: ${result}`);
          return result;
        } catch (e) {
          // console.log(`Error: ${e}`);
          throw e;
        } finally {
          console.groupEnd()
        }
      }
    }
    return descriptor;
  }
}
