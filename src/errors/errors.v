module errors

// ExitCode is the status code that is passed to the exit
// function upon fatal errors. Typically caused by bad
// Frabjous code passed to the compiler.
pub enum ExitCode {
	tokenizer
}