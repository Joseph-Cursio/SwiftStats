import IndexCore
import index_support

// Top-level code: a real global, used later, and calls into `IndexCore` and
// `index-support`.
let greeting = banner()
print(greeting, layout(3))
print(greeting.count)
