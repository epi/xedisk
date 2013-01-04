import std.conv;
import std.exception;
import std.stdio;
import std.string;
import core.sys.posix.fcntl;
import core.sys.posix.unistd;

private
{
extern(C)
int SerialPort_open(const(char)* name);

extern(C)
int SerialPort_setBaudRate(int fd, uint br);

enum TCIFLUSH  = 0;
enum TCOFLUSH  = 1;
enum TCIOFLUSH = 2;

extern(C)
int tcflush(int fd, int queue_selector);
}

class SerialPort
{
	this(string name)
	{
		const namez = toStringz(name);
		_fd = SerialPort_open(namez);
		errnoEnforce(_fd >= 0, name);
	}

	~this()
	{
		close();
	}

	void close()
	{
		if (_fd)
		{
			.close(_fd);
			_fd = 0;
		}
	}

	@property void baudRate(uint br)
	{
		if (br == _baudRate)
			return;
		errnoEnforce(SerialPort_setBaudRate(_fd, br) == 0);
		_baudRate = br;
	}

	size_t read(ubyte[] buffer)
	{
		auto res = core.sys.posix.unistd.read(_fd, buffer.ptr, buffer.length);
		errnoEnforce(res >= 0, "read");
		writefln("READ  %(%02x%| %)", buffer[0 .. res]);
		return res;
	}

	void write(ubyte[] buffer)
	{
		writefln("WRITE %(%02x%| %)", buffer);
		while (buffer.length)
		{
			auto res = core.sys.posix.unistd.write(
				_fd, buffer.ptr, buffer.length);
			errnoEnforce(res >= 0, "write");
			buffer = buffer[res .. $];
		}
		tcflush(_fd, TCOFLUSH);
	}

	int _baudRate;
	int _fd;
}
