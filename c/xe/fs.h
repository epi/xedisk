#ifndef _XEFILESYSTEM_H__
#define _XEFILESYSTEM_H__

#ifdef __cplusplus
extern "C" {
#endif

#include <xe/disk.h>

typedef struct XeFileSystem XeFileSystem;

XeFileSystem *XeFileSystem_Open(XeDisk *pDisk);
void XeFileSystem_Close(XeFileSystem *pFS);
const char *XeFileSystem_GetType(XeFileSystem *pFS);
unsigned XeFileSystem_GetFreeSectors(XeFileSystem *pFS);
unsigned long long XeFileSystem_GetFreeBytes(XeFileSystem *pFS);

#ifdef __cplusplus
} // extern "C"
#endif

#endif /* _XEFILESYSTEM_H__ */
