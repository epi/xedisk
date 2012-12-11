#include <xe/disk.h>
#include <xe/fs.h>
#include <xe/stream.h>

#include <fuse.h>

#include <stdio.h>
#include <string.h>
#include <errno.h>
#include <fcntl.h>

static XeDisk *pDisk = NULL;
static XeFileSystem *pFileSystem = NULL;

static int XeFuse_getattr(const char *path, struct stat *stbuf)
{
	memset(stbuf, 0, sizeof(struct stat));
	if (strcmp(path, "/") == 0)
	{
		stbuf->st_mode = S_IFDIR | 0755;
		stbuf->st_nlink = 2;
		return 0;
	}
	else
	{
		XeDirectory *pRootDir = XeFileSystem_GetRootDirectory(pFileSystem);
		XeEntry *pEntry = NULL;
		if (!pRootDir)
			return -ENOENT;
		pEntry = XeDirectory_Find(pRootDir, path);
		if (!pEntry)
		{
			XeDirectory_Free(pRootDir);
			return -ENOENT;
		}
		if (XeEntry_IsDirectory(pEntry))
		{
			stbuf->st_mode = S_IFDIR | 0555;
			stbuf->st_nlink = 2;
		}
		else if (XeEntry_IsFile(pEntry))
		{
			stbuf->st_mode = S_IFREG | 0444;
			stbuf->st_nlink = 2;
		}
		else
		{
			stbuf->st_mode = S_IFREG | 0000;
			stbuf->st_nlink = 2;
		}
		stbuf->st_size = XeEntry_GetSize(pEntry);
		stbuf->st_mtime = XeEntry_GetTimeStamp(pEntry);
		XeEntry_Free(pEntry);
		XeDirectory_Free(pRootDir);
		return 0;
	}
}

typedef struct
{
	void *buf;
	fuse_fill_dir_t filler;
}
CallbackData;

static int XeFuse_readdir_callback(void *data, XeEntry *pEntry)
{
	((CallbackData *)data)->filler(((CallbackData *)data)->buf,
		XeEntry_GetName(pEntry), NULL, 0);
	return 0;
}

static int XeFuse_readdir(
	const char *path, void *buf, fuse_fill_dir_t filler,
	off_t offset, struct fuse_file_info *fi)
{
	(void) offset;
	(void) fi;

	int result = 0;
	XeDirectory *pRootDir = NULL;
	XeEntry *pEntry = NULL;
	XeDirectory *pDir = NULL;

	pRootDir = XeFileSystem_GetRootDirectory(pFileSystem);
	if (!pRootDir)
		return -ENOENT;
	pEntry = XeDirectory_Find(pRootDir, path);
	if (!pEntry)
	{
		result = -ENOENT;
		goto cleanup_root;
	}
	pDir = XeEntry_AsDirectory(pEntry);
	if (!pDir)
	{
		result = -ENOENT;
		goto cleanup_entry;
	}

	filler(buf, ".", NULL, 0);
	filler(buf, "..", NULL, 0);

	CallbackData data;
	data.buf = buf;
	data.filler = filler;
	XeDirectory_Enumerate(pDir, &XeFuse_readdir_callback, &data);

	XeDirectory_Free(pDir);
cleanup_entry:
	XeEntry_Free(pEntry);
cleanup_root:
	XeDirectory_Free(pRootDir);
	return result;
}

static int XeFuse_open(const char *path, struct fuse_file_info *fi)
{
	int result = 0;
	XeDirectory *pRootDir = NULL;
	XeEntry *pEntry = NULL;
	pRootDir = XeFileSystem_GetRootDirectory(pFileSystem);
	if (!pRootDir)
		return -ENOENT;
	pEntry = XeDirectory_Find(pRootDir, path);
	if (!pEntry)
	{
		XeDirectory_Free(pRootDir);
		result = -ENOENT;
		goto cleanup_root;
	}
	if (!XeEntry_IsFile(pEntry))
	{
		result = -ENOENT;
		goto cleanup_entry;
	}
	if ((fi->flags & 3) != O_RDONLY)
	{
		result = -EACCES;
		goto cleanup_entry;
	}

	// ...

cleanup_entry:
	XeEntry_Free(pEntry);
cleanup_root:
	XeDirectory_Free(pRootDir);
	return result;
}

static int XeFuse_read(const char *path, char *buf, size_t size, off_t offset,
	struct fuse_file_info *fi)
{
	int result = 0;
	XeDirectory *pRootDir = NULL;
	XeEntry *pEntry = NULL;
	XeFile *pFile = NULL;
	XeInputStream *pStream = NULL;
	size_t pos;
	(void) fi;
	fprintf(stderr, "%s, %p, %d, %d\n", path, buf, (int) size, (int) offset);
	pRootDir = XeFileSystem_GetRootDirectory(pFileSystem);
	if (!pRootDir)
		return -ENOENT;
	pEntry = XeDirectory_Find(pRootDir, path);
	if (!pEntry)
	{
		XeDirectory_Free(pRootDir);
		result = -ENOENT;
		goto cleanup_root;
	}
	if (!XeEntry_IsFile(pEntry))
	{
		result = -ENOENT;
		goto cleanup_entry;
	}
	if ((fi->flags & 3) != O_RDONLY)
	{
		result = -EACCES;
		goto cleanup_entry;
	}
	pFile = XeEntry_AsFile(pEntry);
	if (!pFile)
	{
		result = -ENOMEM;
		goto cleanup_entry;
	}
	pStream = XeFile_OpenReadOnly(pFile);
	if (!pStream)
	{
		result = -EACCES;
		goto cleanup_file;
	}
	// skip
	for (pos = 0; pos < offset; )
	{
		size_t blksize = size;
		if (pos + blksize > offset)
			blksize = offset - pos;
		if (XeInputStream_Read(pStream, buf, blksize) != blksize)
		{
			result = 0;
			goto cleanup_stream;
		}
		pos += blksize;
	}
	// and read
	result = XeInputStream_Read(pStream, buf, size);

cleanup_stream:
	XeInputStream_Free(pStream);
cleanup_file:
	XeFile_Free(pFile);
cleanup_entry:
	XeEntry_Free(pEntry);
cleanup_root:
	XeDirectory_Free(pRootDir);
	return result;

	
/*    len = strlen(XeFuse_str);
    if (offset < len) {
        if (offset + size > len)
            size = len - offset;
        memcpy(buf, XeFuse_str + offset, size);
    } else
        size = 0;

    return size;*/
}

static struct fuse_operations XeFuse_oper =
{
	.getattr	= XeFuse_getattr,
	.readdir	= XeFuse_readdir,
	.open	= XeFuse_open,
	.read	= XeFuse_read,
};

void printUsage(const char *progName)
{
	fprintf(stderr,
		"Usage: %s image_name mountpoint [options]\n\n"
		"Available options:\n"
		" -f    foreground operation\n",
		progName);
}

int main(int argc, char **argv)
{
	const char *filename = NULL;
	const char *mountpoint = NULL;
	const char *fuseargv[4];
	int fuseargc = 0;
	int foreground = 0;
	int i;
	int result;
	fuseargv[fuseargc++] = argv[0];
	for (i = 1; i < argc; ++i)
	{
		if (argv[i][0] == '-')
		{
			if (argv[i][1] == 'f' && !foreground)
			{
				fuseargv[fuseargc++] = argv[i];
				foreground = 1;
			}
			else
			{
				printUsage(argv[0]);
				return 2;
			}
		}
		else if (!filename)
		{
			filename = argv[i];
		}
		else if (!mountpoint)
		{
			mountpoint = argv[i];
			fuseargv[fuseargc++] = argv[i];
		}
		else
		{
			printUsage(argv[0]);
			return 2;
		}
	}
	fuseargv[fuseargc++] = "-s";
	if (!filename || !mountpoint)
	{
		printUsage(argv[0]);
		return 2;
	}

	XeDisk_Init();
	pDisk = XeDisk_OpenFile(filename, XeDiskOpenMode_ReadOnly);
	if (!pDisk)
	{
		fprintf(stderr, "Error: %s", XeDisk_GetLastError());
		XeDisk_Quit();
		return 1;
	}
	pFileSystem = XeFileSystem_Open(pDisk);
	if (!pFileSystem)
	{
		fprintf(stderr, "Error: %s", XeDisk_GetLastError());
		XeDisk_Free(pDisk);
		XeDisk_Quit();
		return 1;
	}

	result = fuse_main(fuseargc, (char**) fuseargv, &XeFuse_oper);

	XeFileSystem_Free(pFileSystem);
	XeDisk_Free(pDisk);
	XeDisk_Quit();

	return result;
}
