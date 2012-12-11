#ifndef _XE_FS_H__
#define _XE_FS_H__

#ifdef __cplusplus
extern "C" {
#endif

#include <xe/disk.h>
#include <xe/stream.h>

#include <time.h>

typedef struct XeFileSystem XeFileSystem;
typedef struct XeEntry XeEntry;
typedef struct XeDirectory XeDirectory;
typedef struct XeFile XeFile;

/** Creates a new XeFileSystem object which must be freed using
 *  XeFileSystem_Free() when done.
 */
XeFileSystem *XeFileSystem_Open(XeDisk *pDisk);

void XeFileSystem_Free(XeFileSystem *pFS);

const char *XeFileSystem_GetType(XeFileSystem *pFS);
unsigned XeFileSystem_GetFreeSectors(XeFileSystem *pFS);
unsigned long long XeFileSystem_GetFreeBytes(XeFileSystem *pFS);

/** Creates a new XeDirectory object which must be freed using
 *  XeDirectory_Free() when done.
 */
XeDirectory *XeFileSystem_GetRootDirectory(XeFileSystem *pFS);

void XeDirectory_Free(XeDirectory *pDir);
void XeDirectory_Enumerate(
	XeDirectory *pDir,
	int (*callback)(void *pUserData, XeEntry *pEntry),
	void *pUserData);

/** Creates a new XeEntry object which must be freed using
 *  XeEntry_Free() when done.
 */
XeEntry *XeDirectory_Find(XeDirectory *pDir, const char *name);

const char *XeEntry_GetName(XeEntry *pEntry);
unsigned long long XeEntry_GetSize(XeEntry *pEntry);
time_t XeEntry_GetTimeStamp(XeEntry *pEntry);
int XeEntry_IsDirectory(XeEntry *pEntry);
int XeEntry_IsFile(XeEntry *pEntry);
void XeEntry_Free(XeEntry *pEntry);

/** Creates a new XeDirectory object which must be freed using
 *  XeDirectory_Free() when done.
 */
XeDirectory *XeEntry_AsDirectory(XeEntry *pEntry);

/** Creates a new XeFile object which must be freed using
 *  XeFile_Free() when done.
 */
XeFile *XeEntry_AsFile(XeEntry *pEntry);

void XeFile_Free(XeFile *pFile);

/** Creates a new XeInputStream object which must be freed using
 *  XeInputStream_Free() when done.
 */
XeInputStream *XeFile_OpenReadOnly(XeFile *pFile);

#ifdef __cplusplus
} // extern "C"
#endif

#endif /* _XE_FS_H__ */
