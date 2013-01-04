//import xe.disk;
//import xe.disk_impl.all;
import siodevice;
import core.sys.posix.unistd;

class DiskDrive : SioDevice
{
	this(ubyte dev)
	{
		_dev = dev;
	}

	override void execute(ubyte dev, ubyte cmd, ubyte aux1, ubyte aux2)
	{
		switch (cmd)
		{
		case 0x53: getStatus(); break;
		case 0x52: readSector(aux1, aux2); break;
		default:
			_writer.writeByte(19200, 0x4E);
		}
	}

	override @property void writer(SioWriter writer)
	{
		_writer = writer;
	}

	void getStatus()
	{
		_writer.writeByte(19200, 0x41);
		.usleep(1000);
		_writer.writeByte(19200, 0x43);
		.usleep(250);
		_writer.write(19200, [cast(ubyte) 0x28, 0xFF, 0, 0, 0]);
	}

	ubyte[257] y;
	void readSector(ubyte aux1, ubyte aux2)
	{
		_writer.writeByte(19200, 0x41);
		.usleep(1000);
		_writer.writeByte(19200, 0x43);
		.usleep(250);
		uint sec = aux1 | (aux2 << 8);
		if (sec >= 1 && sec <= 3)
			_writer.write(19200, y[0 .. 129]);
		else
			_writer.write(19200, y[0 .. 257]);
	}

private:
	SioWriter _writer;
	ubyte _dev;
}
