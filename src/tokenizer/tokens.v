module tokenizer

pub type Token = Statement | Expression | EndOfFile

// EndOfFile is the position which the end of the file was
// encountered at.
pub type EndOfFile = int
pub type Expression = InlineIfExpression
pub type Statement = ModuleStatement | IfStatement

pub struct ModuleStatement {
pub mut:
	start_pos int
	len int
	module_name string
}

pub struct IfStatement {
pub mut:
	start_pos int
	len int
}

pub struct InlineIfExpression {
pub mut:
	start_pos int
	len int
}