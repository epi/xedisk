#ifndef _XEDISK_H__
#define _XEDISK_H__

#ifdef __cplusplus
extern "C" {
#endif

#include <xe/disk.h>

typedef struct XeFileSystem XeFileSystem;

XeFileSystem* XeFileSystem(XeDisk* pDisk);

void XeFileSystem_close(XeFileSystem *pFS);

#ifdef __cplusplus
} // extern "C"
#endif

#endif /* _XEDISK_H__ */
