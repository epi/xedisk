#include <xe/disk.h>
#include <xe/fs.h>

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
			XeDisk_GetSectorCount(pDisk),
			XeDisk_GetSectorSize(pDisk));
		XeFileSystem* pFileSystem = XeFileSystem_Open(pDisk);
		if (pFileSystem)
		{
			printf("File system: %s\n%d free sectors\n%lld free bytes\n",
				XeFileSystem_GetType(pFileSystem),
				XeFileSystem_GetFreeSectors(pFileSystem),
				XeFileSystem_GetFreeBytes(pFileSystem));
			XeFileSystem_Free(pFileSystem);
		}
		XeDisk_Free(pDisk);
	}
	XeDisk_Quit();
	return 0;
}
