#include <xe/disk.h>

#include <stdio.h>
#include <stdlib.h>

int main(int argc, char** argv)
{
	unsigned numSectors = 720;
	unsigned sectorSize = 256;
	XeDisk* pDisk = NULL;
	if (argc < 2 || argc > 4)
	{
		fprintf(stderr, "Usage:\n%s file_name [num_sectors [sector_size]]\n",
			argv[0]);
		return 2;
	}
	XeDisk_Init();
	if (argc > 2)
	{
		numSectors = strtod(argv[2], NULL);
		if (argc > 3)
			sectorSize = strtod(argv[3], NULL);
	}
	pDisk = XeDisk_CreateFile(argv[1], "atr", numSectors, sectorSize);
	if (!pDisk)
	{
		fprintf(stderr, "Error: %s\n", XeDisk_GetLastError());
		XeDisk_Quit();
		return 1;
	}
	else
	{
		printf("%s: %d sectors * %d bytes\n",
			XeDisk_GetType(pDisk),
			XeDisk_GetSectors(pDisk),
			XeDisk_GetSectorSize(pDisk)),
		XeDisk_Close(pDisk);
	}
	XeDisk_Quit();
	return 0;
}
