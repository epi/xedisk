interface SioWriter
{
	void writeByte(uint baudRate, ubyte b);
	void write(uint baudRate, ubyte[] data);
}

interface SioDevice
{
	@property void writer(SioWriter writer);
	void execute(ubyte dev, ubyte cmd, ubyte aux1, ubyte aux2);
//	void onClose();
}
