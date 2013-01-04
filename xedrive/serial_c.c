#include <fcntl.h>
#include <unistd.h>
#include <termios.h>
#include <sys/ioctl.h>
#include <linux/serial.h>
#include <errno.h>
#include <stdio.h>

int SerialPort_open(const char *name)
{
	int res;
	int fd = open(name, O_RDWR | O_NOCTTY /*| O_NDELAY*/);
	if (fd < 0)
		return fd;
	struct termios config;
	res = tcgetattr(fd, &config);
	if (res < 0)
	{
		close(fd);
		return res;
	}
	config.c_iflag &=
		~(IGNBRK | BRKINT | ICRNL | INLCR | PARMRK | INPCK | ISTRIP | IXON);
	config.c_oflag &=
		~(OCRNL | ONLCR | ONLRET | ONOCR | OFILL | OPOST);
	config.c_lflag &= ~(ECHO | ECHONL | ICANON | IEXTEN | ISIG);
	config.c_cflag &= ~(CSIZE | PARENB | CSTOPB);
	config.c_cflag |= CS8;
	config.c_cc[VMIN] = 1;
	config.c_cc[VTIME] = 0;
	res = tcsetattr(fd, TCSAFLUSH, &config);
	if (res < 0)
	{
		close(fd);
		return res;
	}
	return fd;
}

int SerialPort_setBaudRate(int fd, unsigned br)
{
	struct termios config;
	struct serial_struct ss;
	unsigned closestSpeed;
	int res;

	res = tcgetattr(fd, &config);
	if (res < 0)
		return res;

	res = ioctl(fd, TIOCGSERIAL, &ss);
	if (res < 0)
		return res;
	ss.flags = (ss.flags & ~ASYNC_SPD_MASK) | ASYNC_SPD_CUST;
	ss.custom_divisor = (ss.baud_base + (br / 2)) / br;
	closestSpeed = ss.baud_base / ss.custom_divisor;
	if (closestSpeed < br * 95 / 100 || closestSpeed > br * 105 / 100)
	{
		errno = EINVAL;
		return -1;
	}
	res = ioctl(fd, TIOCSSERIAL, &ss);
	if (res < 0)
		return res;
	if (cfsetispeed(&config, B38400) != 0
	 || cfsetospeed(&config, B38400) != 0)
	 	return -1;

	res = tcsetattr(fd, TCSAFLUSH, &config);
	if (res < 0)
	{
		close(fd);
		return res;
	}

	 printf("%d %d\n", closestSpeed, ss.custom_divisor);
	 return 0;
}
