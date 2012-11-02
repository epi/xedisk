// Written in the D programming language

/*
exception.d - classes for exceptions thrown from the xedisk library.
Copyright (C) 2010-2012 Adrian Matoga

xedisk is free software: you can redistribute it and/or modify
it under the terms of the GNU General Public License as published by
the Free Software Foundation, either version 3 of the License, or
(at your option) any later version.

xedisk is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
GNU General Public License for more details.

You should have received a copy of the GNU General Public License
along with xedisk.  If not, see <http://www.gnu.org/licenses/>.
*/

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
