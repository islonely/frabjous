module tokenizer

import errors
import strings
import term

pub const (
	alpha_lower = 'abcdefghijklmnopqrstuvwxyz'.runes()
	alpha_upper = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ'.runes()
	digits = '0123456789'.runes()
	whitespace = ' \t\n\r\f'.runes()
)

// TokenizerState is the states the Tokenizer may be in.
enum TokenizerState {
	between_module_keyword_and_name
	in_identifier
	in_module_name
	start
}

// Tokenizer converts raw text into Tokens.
pub struct Tokenizer {
pub:
	source []rune
mut:
	buffer strings.Builder = strings.new_builder(100)
	current_token Token = EndOfFile(-1)
pub mut:
	pos int
	token_start_pos int
	token_len int
__global:
	state TokenizerState = .start
}

fn (tokenizer Tokenizer) pos_to_line_number(pos int) int {
	mut line_count := 1
	for i, r in tokenizer.source {
		if r == `\n` {
			line_count++
		}
		if i == pos {
			return line_count
		}
	}
	return -1
}

fn split_into_80_chars(str string) []string {
	mut chunks := []string{cap: str.len % 80 + 1}
	mut line := strings.new_builder(500)
	for i, r in str {
		if i % 80 == 0 {
			chunks << line.str()
			line = strings.new_builder(500)
		}
		line.write_rune(r)
	}
	return chunks
}

[direct_array_access]
fn (tokenizer Tokenizer) get_error_context() string {
	mut start_pos := tokenizer.token_start_pos
	mut line_count := 3
	for start_pos > 0 && line_count > 0 {
		start_pos--
		if tokenizer.source[start_pos] == `\n` {
			line_count--
		}
	}
	line_count = 3
	mut end_pos := tokenizer.pos
	for end_pos < tokenizer.source.len && line_count > 0 {
		end_pos++
		if tokenizer.source[start_pos] == `\n` {
			line_count--
		}
	}
	mut start_line_number := tokenizer.pos_to_line_number(start_pos)
	mut lines := tokenizer.source[start_pos..end_pos].string().split_into_lines()
	last_line_number := start_line_number + lines.len
	pad_line_number := fn [last_line_number] (line_number int) string {
		pad := last_line_number.str().len - line_number.str().len
		return ' '.repeat(pad) + line_number.str()
	}
	for i, line in lines {
		lines[i] = '${pad_line_number(start_line_number)} | ${line}'
		start_line_number++
	}
	return '='.repeat(80) + '\n${lines.join('\n')}\n' + '='.repeat(80)
}

fn (tokenizer Tokenizer) error(msg string) string {
	mut error_builder := strings.new_builder(500)
	error_builder.writeln(term.bright_red('error') + ': ${msg}')
	error_builder.writeln(tokenizer.get_error_context())
	return error_builder.str()
}

// exit_with_error prints an error message before exiting the
// program.
[inline]
fn (tokenizer Tokenizer) print_error(msg string) {
	eprintln(tokenizer.error(msg))
	exit(int(errors.ExitCode.tokenizer))
}

// current_rune returns the current character from the raw text.
[inline; direct_array_access]
pub fn (tokenizer Tokenizer) current_rune() ?rune {
	return tokenizer.source[tokenizer.pos] or { return none }
}

// consume_rune returns the current character from the raw text and
// moves the cursor position forward once. Returns none if the last
// character has already been consumed.
[inline; direct_array_access]
pub fn (mut tokenizer Tokenizer) consume_rune() ?rune {
	defer {
		if _likely_(tokenizer.pos < tokenizer.source.len) {
			tokenizer.pos++
		}
	}
	return tokenizer.source[tokenizer.pos] or { return none }
}

// emit_token continues tokenizing the raw text and returns the next
// Token. If an invalid token is encountered, then an error is returned
// instead.
pub fn (mut tokenizer Tokenizer) emit_token() !Token {
	token := match tokenizer.state {
		.between_module_keyword_and_name { tokenizer.state_between_module_keyword_and_name()! }
		.in_identifier { tokenizer.state_in_identifier()! }
		.in_module_name { tokenizer.state_in_module_name()! }
		.start { tokenizer.state_start()! }
	}
	return token
}

// state_start emits tokens when in the start state.
fn (mut tokenizer Tokenizer) state_start() !Token {
	current_rune := tokenizer.consume_rune() or {
		return EndOfFile(tokenizer.pos)
	}

	if current_rune == `_` || current_rune in alpha_lower {
		tokenizer.buffer.write_rune(current_rune)
		tokenizer.state = .in_identifier
		// This will always be -1 because  tokenizer.consume_rune() propagates
		// the position.
		tokenizer.token_start_pos = tokenizer.pos - 1
		tokenizer.token_len = 1
		return tokenizer.state_in_identifier()!
	}

	return error('invalid character in start state')
}

// state_in_identfier adds valid runes to the buffer until
// whitespace is encountered. It then returns an identifier (const,
// variable, module name, etc.) or switches to another state in
// the case that the word in the buffer is a keyword.
fn (mut tokenizer Tokenizer) state_in_identifier() !Token {
	current_rune := tokenizer.consume_rune() or {
		return EndOfFile(tokenizer.pos)
	}

	if current_rune in whitespace {
		identifier := tokenizer.buffer.str()
		match identifier {
			'module' {
				tokenizer.current_token = Statement(ModuleStatement{
					start_pos: tokenizer.token_start_pos
					len: tokenizer.token_len
				})

				tokenizer.state = .between_module_keyword_and_name
				return tokenizer.state_between_module_keyword_and_name()!
			}
			else {
				return error('variable')
			}
		}
	}

	tokenizer.buffer.write_rune(current_rune)
	tokenizer.token_len++
	return tokenizer.state_in_identifier()!
}

fn (mut tokenizer Tokenizer) state_between_module_keyword_and_name() !Token {
	mut current_rune := tokenizer.consume_rune() or {
		return EndOfFile(tokenizer.pos)
	}

	for {
		if current_rune !in whitespace { break }
		// ignore whitespace
		current_rune = tokenizer.consume_rune() or {
			return EndOfFile(tokenizer.pos)
		}
	}

	// module name must start with a lowercase letter
	if current_rune in alpha_lower {
		tokenizer.buffer = strings.new_builder(100)
		tokenizer.buffer.write_rune(current_rune)
		tokenizer.state = .in_module_name
		return tokenizer.state_in_module_name()!
	}

	// return error('Invalid start of module name: ${current_rune}\nModule names must begin with a lowercase letter.')
	tokenizer.print_error('Module names must begin with a lowercase letter.')
	exit(int(errors.ExitCode.tokenizer))
}

fn (mut tokenizer Tokenizer) state_in_module_name() !Token {
	mut current_rune := tokenizer.consume_rune() or {
		return EndOfFile(tokenizer.pos)
	}

	for current_rune == `_` || current_rune in alpha_lower || current_rune in digits {
		tokenizer.buffer.write_rune(current_rune)
		current_rune = tokenizer.consume_rune() or {
			return EndOfFile(tokenizer.pos)
		}
	}

	if current_rune in whitespace {
		// ignore
		current_rune = tokenizer.consume_rune() or {
			return EndOfFile(tokenizer.pos)
		}
	}

	if current_rune == `;` {
		mut module_statement := tokenizer.current_token as Statement as ModuleStatement
		module_statement.module_name = tokenizer.buffer.str()
		return Statement(module_statement)
	}

	return error('Invalid character in module name: ${current_rune}\nModule names can only container lowercase letters, underscores, and integers.')
}