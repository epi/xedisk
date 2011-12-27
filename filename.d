import std.string;
import std.stdio;

struct FileName
{
	string fn;

	this(string fn)
	{
		this.fn = fn;
	}

	this(ubyte[] rawnameext)
	{
		this(rawnameext[0 .. 8], rawnameext[8 .. 11]);
	}

	this(ubyte[] rawname, ubyte[] rawext)
	{
		void custr(ubyte[] str)
		{
			foreach (c; str)
				fn ~= (c >= 0x20 && c <= 0x7E) ? c : '_';
			fn = fn.stripRight();
		}
		
		custr(rawname);
		fn = fn ~ ".";
		custr(rawext);
		fn = fn.stripRight().chomp(".");
	}

	immutable(ubyte[]) expand()
	{
		auto result = new char[11];
		size_t i, j;
		while (i < 11 && j < fn.length)
		{
			auto b = fn[j++];
			size_t en;
			switch (b)
			{
			case '.':
				while (i < 8)
					result[i++] = ' ';
				break;
			case '*':
				en = (i < 8) ? 8 : 11;
				while (i < en)
					result[i++] = '?';
				break;
			default:
				result[i++] = b;
			}
		}
		while (i < 11)
			result[i++] = ' ';
		toUpperInPlace(result);
		return cast(immutable(ubyte[])) result.idup;
	}
	
	bool match(string mask)
	{
		auto efn = cast(string) expand();
		auto em = cast(string) FileName(mask).expand();
		assert (efn.length == em.length, "|" ~ efn ~ "|" ~ em ~ "|");
		foreach (i, m; em)
		{
			if (m != '?' && efn[i] != m)
				return false;
		}
		return true;
	}

	string toString()
	{
		return fn;
	}
	
	string opCast(T)() if (is(T == string))
	{
		return fn;
	}
}

string[] splitPath(string path)
{
	string[] result;
	auto r = path.split("/");
	foreach (s; r)
	{
		if (s.length)
			result ~= s.idup;
	}
	return result;
}
