module xe.exception;
import std.string;

class XeException : Exception
{
	this(string msg, uint errorCode = 0, string file = __FILE__, size_t line = __LINE__, Throwable next = null)
	{
		super(msg, file, line, next);
		_errorCode = errorCode;
	}

	@property uint errorCode() pure nothrow { return _errorCode; }

	override @property string toString()
	{
		if (_errorCode)
			return format("Error #%d: %s", _errorCode, msg);
		else
			return msg;
	}

	private uint _errorCode;
}
