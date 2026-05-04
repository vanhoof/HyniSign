// HyniSign — strip kSecAttrAccessGroup from Security.framework calls so
// re-signed Minecraft Bedrock can store its Xbox Live device-identity key in
// the keychain. Without this, SecKeyCreateRandomKey fails with -34018
// (errSecMissingEntitlement) because the original Mojang access group is
// unreachable under the new signing identity.
//
// Uses fishhook to rebind the lazy-binding pointer slots in the main
// minecraftpe binary. We don't try to patch the Security framework itself;
// PAC + write-protected system code pages on iPadOS 26 / arm64e make
// MSHookFunction unreliable for that.

#import <Foundation/Foundation.h>
#import <Security/Security.h>
#import <stdbool.h>
#import "access_group.h"
#import "fishhook.h"

#define LOG(fmt, ...) NSLog(@"[HyniSign] " fmt, ##__VA_ARGS__)

#ifdef HYNISIGN_VERBOSE
#define VLOG(fmt, ...) LOG(fmt, ##__VA_ARGS__)
#else
#define VLOG(fmt, ...) do { } while (0)
#endif

static OSStatus (*orig_SecItemAdd)(CFDictionaryRef, CFTypeRef *);
static OSStatus (*orig_SecItemCopyMatching)(CFDictionaryRef, CFTypeRef *);
static OSStatus (*orig_SecItemUpdate)(CFDictionaryRef, CFDictionaryRef);
static OSStatus (*orig_SecItemDelete)(CFDictionaryRef);
static SecKeyRef (*orig_SecKeyCreateRandomKey)(CFDictionaryRef, CFErrorRef *);
static OSStatus (*orig_SecKeyGeneratePair)(CFDictionaryRef, SecKeyRef *, SecKeyRef *);

// LOG fires only when we actually rewrote a query (rare and informative);
// VLOG fires on every call (chatty; gated by HYNISIGN_VERBOSE).

static OSStatus my_SecItemAdd(CFDictionaryRef attrs, CFTypeRef *result) {
    bool c = false;
    CFDictionaryRef d = HyniSignCopyStripped(attrs, &c);
    OSStatus s = orig_SecItemAdd(d, result);
    if (c) LOG(@"SecItemAdd stripped, status=%d", (int)s);
    else   VLOG(@"SecItemAdd status=%d", (int)s);
    if (c) CFRelease(d);
    return s;
}

static OSStatus my_SecItemCopyMatching(CFDictionaryRef q, CFTypeRef *result) {
    bool c = false;
    CFDictionaryRef d = HyniSignCopyStripped(q, &c);
    OSStatus s = orig_SecItemCopyMatching(d, result);
    if (c) LOG(@"SecItemCopyMatching stripped, status=%d", (int)s);
    else   VLOG(@"SecItemCopyMatching status=%d", (int)s);
    if (c) CFRelease(d);
    return s;
}

static OSStatus my_SecItemUpdate(CFDictionaryRef q, CFDictionaryRef u) {
    bool c1 = false, c2 = false;
    CFDictionaryRef qd = HyniSignCopyStripped(q, &c1);
    CFDictionaryRef ud = HyniSignCopyStripped(u, &c2);
    OSStatus s = orig_SecItemUpdate(qd, ud);
    if (c1 || c2) LOG(@"SecItemUpdate stripped (q=%d u=%d), status=%d", c1, c2, (int)s);
    else          VLOG(@"SecItemUpdate status=%d", (int)s);
    if (c1) CFRelease(qd);
    if (c2) CFRelease(ud);
    return s;
}

static OSStatus my_SecItemDelete(CFDictionaryRef q) {
    bool c = false;
    CFDictionaryRef d = HyniSignCopyStripped(q, &c);
    OSStatus s = orig_SecItemDelete(d);
    if (c) LOG(@"SecItemDelete stripped, status=%d", (int)s);
    else   VLOG(@"SecItemDelete status=%d", (int)s);
    if (c) CFRelease(d);
    return s;
}

static SecKeyRef my_SecKeyCreateRandomKey(CFDictionaryRef params, CFErrorRef *error) {
    bool c = false;
    CFDictionaryRef p = HyniSignCopyStripped(params, &c);
    SecKeyRef k = orig_SecKeyCreateRandomKey(p, error);
    if (c) LOG(@"SecKeyCreateRandomKey stripped, ok=%d", k != NULL);
    else   VLOG(@"SecKeyCreateRandomKey ok=%d", k != NULL);
    if (c) CFRelease(p);
    return k;
}

static OSStatus my_SecKeyGeneratePair(CFDictionaryRef params, SecKeyRef *pub, SecKeyRef *priv) {
    bool c = false;
    CFDictionaryRef p = HyniSignCopyStripped(params, &c);
    OSStatus s = orig_SecKeyGeneratePair(p, pub, priv);
    if (c) LOG(@"SecKeyGeneratePair stripped, status=%d", (int)s);
    else   VLOG(@"SecKeyGeneratePair status=%d", (int)s);
    if (c) CFRelease(p);
    return s;
}

%ctor {
    LOG(@"loading");
    struct rebinding rebs[] = {
        { "SecItemAdd",            (void *)my_SecItemAdd,            (void **)&orig_SecItemAdd },
        { "SecItemCopyMatching",   (void *)my_SecItemCopyMatching,   (void **)&orig_SecItemCopyMatching },
        { "SecItemUpdate",         (void *)my_SecItemUpdate,         (void **)&orig_SecItemUpdate },
        { "SecItemDelete",         (void *)my_SecItemDelete,         (void **)&orig_SecItemDelete },
        { "SecKeyCreateRandomKey", (void *)my_SecKeyCreateRandomKey, (void **)&orig_SecKeyCreateRandomKey },
        { "SecKeyGeneratePair",    (void *)my_SecKeyGeneratePair,    (void **)&orig_SecKeyGeneratePair },
    };
    int rc = rebind_symbols(rebs, sizeof(rebs) / sizeof(rebs[0]));
    LOG(@"rebind_symbols returned %d, hooks installed", rc);
}
