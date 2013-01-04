import std.algorithm;
import std.stdio;
import std.string;

import serial;
import siodevice;
import sioserver;
import disk;

void main()
{
	auto port = new SerialPort("/dev/ttyUSB0");
	scope (exit) port.close();
	auto server = new SioServer(port);
	scope (exit) server.close();
	server.registerDevice(0x32, new DiskDrive(0x32));
	server.run();
}
