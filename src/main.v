module main

import tokenizer

const test_src = 'module standard;'

fn main() {
	mut t := tokenizer.Tokenizer{source: test_src.runes()}
	token := t.emit_token() or {
		println(t)
		println('err: ${err.msg()}')
		exit(1)
	}
	println(token)
}
