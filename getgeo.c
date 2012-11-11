#include <linux/hdreg.h>
#include <fcntl.h>
#include <unistd.h>
#include <sys/ioctl.h>

int getDriveGeometry(const char *dev, struct hd_geometry *geom)
{
	int r;
	int fd = open(dev, O_RDONLY);
	if (fd < 0)
		return -1;
	r = ioctl(fd, HDIO_GETGEO, geom);
	close(fd);
	return r;
}
