module xe.test;

public import std.stdio;
import std.exception;
import std.typecons;
import std.c.stdlib;

template Test(string s)
{
	enum Test =
	q{
		stderr.write(} ~ `"Test '` ~ s ~ `'... "` ~ q{);
		scope(success) stderr.writeln("ok");
		scope(failure) stderr.writeln("failed");
	};
}

void sink(T)(T value) {}

version(Linux)
{
	extern (C)
	FILE* fmemopen(void* buf, size_t size, const(char)* mode);

	extern (C)
	FILE *open_memstream(char** ptr, size_t* sizeloc);
}
else
{
	import std.c.stdio;
}

auto captureConsole(lazy void dg, string cin = "\n")
{
	version(Linux)
	{
		FILE* fp_cin = enforce(fmemopen(cast(void*) cin.ptr, cin.length, "r"),
			"fmemopen failed");
		scope (exit) fclose(fp_cin);

		size_t cout_size;
		char* cout_ptr = null;
		FILE* fp_cout = open_memstream(&cout_ptr, &cout_size);
		if (!fp_cout)
			throw new Exception("open_memstream failed for cout");
		scope (exit) free(cout_ptr);
		scope (exit) fclose(fp_cout);

		size_t cerr_size;
		char* cerr_ptr = null;
		FILE* fp_cerr = open_memstream(&cerr_ptr, &cerr_size);
		if (!fp_cerr)
			throw new Exception("open_memstream failed for cerr");
		scope (exit) if (cerr_ptr) free(cerr_ptr);
		scope (exit) fclose(fp_cerr);
	}
	else
	{
		std.file.write(".unittest.cin", cin);
		scope (exit) { remove(".unittest.cin"); }
		FILE* fp_cin = enforce(
			std.c.stdio.fopen(".unittest.cin", "rb"), "fopen failed");
		scope (exit) fclose(fp_cin);

		FILE* fp_cout = enforce(
			std.c.stdio.fopen(".unittest.cout", "wb"), "fopen failed");
		scope (exit) { fclose(fp_cout); remove(".unittest.cout"); }

		FILE* fp_cerr = enforce(
			std.c.stdio.fopen(".unittest.cerr", "wb"), "fopen failed");
		scope (exit) { fclose(fp_cerr); remove(".unittest.cerr"); }
	}

	auto oldstdin = std.stdio.stdin;
	std.stdio.stdin = File.wrapFile(fp_cin);
	scope (exit) std.stdio.stdin = oldstdin;

	auto oldstdout = std.stdio.stdout;
	std.stdio.stdout = File.wrapFile(fp_cout);
	scope (exit) std.stdio.stdout = oldstdout;

	auto oldstderr = std.stdio.stderr;
	std.stdio.stderr = File.wrapFile(fp_cerr);
	scope (exit) std.stdio.stderr = oldstderr;

	auto e = collectException(dg());
	fflush(fp_cout);
	fflush(fp_cerr);

	version(Linux)
	{
		return tuple(
			cout_ptr[0 .. cout_size].idup,
			cerr_ptr[0 .. cerr_size].idup,
			e);
	}
	else
	{
		fclose(fp_cout);
		fclose(fp_cerr);
		return tuple(
			cast(string) std.file.read(".unittest.cout"),
			cast(string) std.file.read(".unittest.cerr"),
			e);
	}
}
