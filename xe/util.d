module xe.util;

import std.exception;
import core.exception;

version(unittest)
{
	import xe.test;
}

C caseWhen(A, B, C, T...)(A value, lazy B toCompare, lazy C resultIfEqual, lazy T other)
{
	if (value == toCompare)
		return resultIfEqual;
	else
	{
		static if (other.length == 0)
			throw new SwitchError("caseWhen(): no match");
		else static if (other.length == 1)
			return other[0];
		else
			return caseWhen(value, other);
	}
}

unittest
{
	mixin(Test!"caseWhen");
	auto numbers = [ "", "one", "two", "three", "four" ];
	foreach (i; 1 .. 5)
	{
		assert(caseWhen(i,
			1, "one",
			2, "two",
			3, "three",
			4, "four") == numbers[i]);
		assertThrown!SwitchError(caseWhen(i, 6, "six"));
	}
	assert (caseWhen(1, 6, "six", "default") == "default");
}
