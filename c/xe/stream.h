#ifndef _XESTREAM_H__
#define _XESTREAM_H__

#ifdef __cplusplus
extern "C" {
#endif

typedef struct XeInputStream XeInputStream;

size_t XeInputStream_Read(XeInputStream *pStream, void *buf, size_t len);
size_t XeInputStream_Free(XeInputStream *pStream);

#ifdef __cplusplus
} // extern "C"
#endif

#endif /* _STREAM_H__ */
