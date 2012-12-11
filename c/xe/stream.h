#ifndef _XE_STREAM_H__
#define _XE_STREAM_H__

#ifdef __cplusplus
extern "C" {
#endif

#include <stdlib.h>

typedef struct XeInputStream XeInputStream;

size_t XeInputStream_Read(XeInputStream *pStream, void *buf, size_t len);
size_t XeInputStream_Free(XeInputStream *pStream);

#ifdef __cplusplus
} // extern "C"
#endif

#endif /* _STREAM_H__ */
