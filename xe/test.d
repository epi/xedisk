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

extern (C)
FILE* fmemopen(void* buf, size_t size, const(char)* mode);

extern (C)
FILE *open_memstream(char** ptr, size_t* sizeloc);

auto captureConsole(lazy void dg, string cin = "\n")
{
	FILE* fp_cin = fmemopen(cast(void*) cin.ptr, cin.length, "r");
	if (!fp_cin)
		throw new Exception("fmemopen failed");
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

	auto oldstdin = stdin;
	stdin = File.wrapFile(fp_cin);
	scope (exit) stdin = oldstdin;

	auto oldstdout = stdout;
	stdout = File.wrapFile(fp_cout);
	scope (exit) stdout = oldstdout;

	auto oldstderr = stderr;
	stderr = File.wrapFile(fp_cerr);
	scope (exit) stderr = oldstderr;

	auto e = collectException(dg());
	fflush(fp_cout);
	fflush(fp_cerr);

	return tuple(
		cout_ptr[0 .. cout_size].idup,
		cerr_ptr[0 .. cerr_size].idup,
		e);
}
