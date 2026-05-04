// access_group.h — pure-C dictionary helper used by HyniSign's hooks.
//
// Extracted from the hook code so it can be unit-tested on the host (macOS)
// without dragging in fishhook, the Foundation runtime, or the Theos build.
// The same source compiles into the iOS dylib and into the macOS test runner.

#ifndef HYNISIGN_ACCESS_GROUP_H
#define HYNISIGN_ACCESS_GROUP_H

#include <CoreFoundation/CoreFoundation.h>
#include <stdbool.h>

#ifdef __cplusplus
extern "C" {
#endif

/// Returns a copy of `in` with `kSecAttrAccessGroup` removed (recursively from
/// the `kSecPrivateKeyAttrs` and `kSecPublicKeyAttrs` sub-dicts when present).
///
/// If no access group is present anywhere, returns `in` unchanged and sets
/// `*didCopy` to false. If a copy was produced, sets `*didCopy` to true and
/// the caller must `CFRelease` the returned dictionary.
///
/// Passing `NULL` returns `NULL` and sets `*didCopy` to false.
CFDictionaryRef HyniSignCopyStripped(CFDictionaryRef in, bool *didCopy);

#ifdef __cplusplus
}
#endif

#endif
