#include <xe/disk.h>

#include <stdio.h>

int main(int argc, char** argv)
{
	if (argc != 2)
	{
		fprintf(stderr, "Usage:\n%s file_name\n", argv[0]);
		return 2;
	}
	XeDisk_Init();
	XeDisk* pDisk = XeDisk_OpenFile(argv[1], XeDiskOpenMode_ReadOnly);
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
