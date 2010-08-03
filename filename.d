import std.string;
import std.stdio;

string cleanUpFileName(ubyte[] name, ubyte[] ext)
{
	char[] result;
	
	void custr(ubyte[] str)
	{
		foreach (c; str)
			result ~= (c >= 0x20 && c <= 0x7E) ? c : '_';
		result = result.stripr();
	}
	
	custr(name);
	result ~= ".";
	custr(ext);
	return result.chomp(".").idup;
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

string expandFileName(string filename)
{
	auto result = new char[11];
	size_t i, j;
	while (i < 11 && j < filename.length)
	{
		auto b = filename[j++];
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
	toupperInPlace(result);
	return result.idup;
}

bool matchFileName(string filename, string mask)
{
	auto efn = expandFileName(filename);
	auto em = expandFileName(mask);
	assert (efn.length == em.length, "|" ~ efn ~ "|" ~ em ~ "|");
	foreach (i, m; em)
	{
		if (m != '?' && efn[i] != m)
			return false;
	}
	return true;
}
