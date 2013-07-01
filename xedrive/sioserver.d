import std.algorithm;
import std.stdio;
import std.string;
import serial;
import siodevice;

struct SioCommand
{
	ubyte device;
	ubyte command;
	ubyte aux1;
	ubyte aux2;
}

class SioServer : SioWriter
{
	this(SerialPort port)
	{
		_port = port;
	}

	~this()
	{
		close();
	}

	void close()
	{
	}

	void run()
	{
		for (;;)
		{
			auto cmd = readCommand();
			writefln(
				"[device = %02X; command = %02X; aux1 = %02X; aux2 = %02X]",
				cmd.device, cmd.command, cmd.aux1, cmd.aux2);
			if (auto device = _devices[cmd.device])
				device.execute(cmd.device, cmd.command, cmd.aux1, cmd.aux2);
		}
	}

	void registerDevice(ubyte id, SioDevice dev)
	{
		if (_devices[id])
			throw new Exception(format("Device %02x already registered", id));
		dev.writer = this;
		_devices[id] = dev;
	}

	override void writeByte(uint baudRate, ubyte b)
	{
		_port.baudRate = baudRate;
		_port.write((&b)[0 .. 1]);
	}

	override void write(uint baudRate, ubyte[] buffer)
	{
		_port.baudRate = baudRate;
		buffer[$ - 1] = checksum(buffer[0 .. $ - 1]);
		_port.write(buffer);
	}

private:
	ubyte checksum(ubyte[] buffer)
	{
		uint temp = reduce!"a + b"(0, buffer);
		return cast(ubyte) ((temp & 0xff) + (temp >> 8));
	}

	auto readCommand()
	{
		ubyte[5] buffer;
		_port.baudRate = 19200;
		for (auto span = buffer[]; span.length; )
			span = span[_port.read(span) .. $];
		while (checksum(buffer[0 .. 4]) != buffer[4])
		{
			ubyte[4] temp = buffer[1 .. 5];
			buffer[0 .. 4] = temp[];
			while (_port.read(buffer[4 .. 5]) < 1) {}
		}
		return SioCommand(buffer[0], buffer[1], buffer[2], buffer[3]);
	}

/*	
	void doEnoSIO(SIOCommand cmd)
	{
		writeByte(0x41);
		.usleep(1000);
		writeByte(0x43);
		setup(125000);
		.usleep(250);
		auto x = new ubyte[0xbc20-0xa00+2];
		foreach (ref q; x)
			q = 0xaa;
		writeSIO(x);
	}

	SIOCommand doCommand()
	{
		auto cmd = readCommand();
		switch (cmd.device)
		{
		case 0x31:
			doDrive1(cmd);
			break;
		case 'e' - 1:
			doEnoSIO(cmd);
			break;
		default:
		}
		return cmd;
	}
*/
private:
	SerialPort _port;
	SioDevice[256] _devices;
}
