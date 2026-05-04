// Unit tests for HyniSignCopyStripped.
//
// Builds for the host (macOS) and links against the same access_group.c that
// ships in the iOS dylib. The function uses only CoreFoundation + Security
// constants, both of which are identical across iOS and macOS for our
// purposes, so host-side tests are representative.

#include <CoreFoundation/CoreFoundation.h>
#include <Security/Security.h>
#include <stdbool.h>
#include <stdio.h>

#include "../access_group.h"

static int passed = 0;
static int failed = 0;

#define CHECK(name, cond) do { \
    if (cond) { \
        printf("  ok    %s\n", name); \
        passed++; \
    } else { \
        printf("  FAIL  %s  (%s:%d)\n", name, __FILE__, __LINE__); \
        failed++; \
    } \
} while (0)

static CFDictionaryRef MakeDict(CFIndex n, const void **keys, const void **vals) {
    return CFDictionaryCreate(NULL, keys, vals, n,
        &kCFTypeDictionaryKeyCallBacks, &kCFTypeDictionaryValueCallBacks);
}

static void test_null_input(void) {
    printf("test_null_input\n");
    bool c = true;
    CFDictionaryRef out = HyniSignCopyStripped(NULL, &c);
    CHECK("NULL input returns NULL", out == NULL);
    CHECK("NULL input clears didCopy", c == false);
}

static void test_passthrough_when_no_access_group(void) {
    printf("test_passthrough_when_no_access_group\n");
    const void *keys[] = { CFSTR("label") };
    const void *vals[] = { CFSTR("test") };
    CFDictionaryRef in = MakeDict(1, keys, vals);

    bool c = true;
    CFDictionaryRef out = HyniSignCopyStripped(in, &c);
    CHECK("returns input when no access group", out == in);
    CHECK("didCopy=false when no access group", c == false);

    CFRelease(in);
}

static void test_strip_top_level(void) {
    printf("test_strip_top_level\n");
    const void *keys[] = { kSecAttrAccessGroup, CFSTR("label") };
    const void *vals[] = { CFSTR("group.id"), CFSTR("test") };
    CFDictionaryRef in = MakeDict(2, keys, vals);

    bool c = false;
    CFDictionaryRef out = HyniSignCopyStripped(in, &c);
    CHECK("didCopy=true when top-level access group present", c == true);
    CHECK("returns a different dict", out != in);
    CHECK("access group removed from output", !CFDictionaryContainsKey(out, kSecAttrAccessGroup));
    CHECK("other keys preserved in output", CFDictionaryContainsKey(out, CFSTR("label")));

    if (c) CFRelease(out);
    CFRelease(in);
}

static void test_strip_private_key_attrs_subdict(void) {
    printf("test_strip_private_key_attrs_subdict\n");
    const void *subKeys[] = { kSecAttrAccessGroup, CFSTR("tag") };
    const void *subVals[] = { CFSTR("group.id"), CFSTR("priv-tag") };
    CFDictionaryRef sub = MakeDict(2, subKeys, subVals);

    const void *keys[] = { kSecPrivateKeyAttrs };
    const void *vals[] = { sub };
    CFDictionaryRef in = MakeDict(1, keys, vals);

    bool c = false;
    CFDictionaryRef out = HyniSignCopyStripped(in, &c);
    CHECK("didCopy=true when private sub-dict has access group", c == true);

    CFDictionaryRef outSub = (CFDictionaryRef)CFDictionaryGetValue(out, kSecPrivateKeyAttrs);
    CHECK("private sub-dict still present", outSub != NULL);
    CHECK("private sub-dict access group removed", !CFDictionaryContainsKey(outSub, kSecAttrAccessGroup));
    CHECK("private sub-dict other keys preserved", CFDictionaryContainsKey(outSub, CFSTR("tag")));

    if (c) CFRelease(out);
    CFRelease(sub);
    CFRelease(in);
}

static void test_strip_public_key_attrs_subdict(void) {
    printf("test_strip_public_key_attrs_subdict\n");
    const void *subKeys[] = { kSecAttrAccessGroup };
    const void *subVals[] = { CFSTR("group.id") };
    CFDictionaryRef sub = MakeDict(1, subKeys, subVals);

    const void *keys[] = { kSecPublicKeyAttrs };
    const void *vals[] = { sub };
    CFDictionaryRef in = MakeDict(1, keys, vals);

    bool c = false;
    CFDictionaryRef out = HyniSignCopyStripped(in, &c);
    CHECK("didCopy=true when public sub-dict has access group", c == true);

    CFDictionaryRef outSub = (CFDictionaryRef)CFDictionaryGetValue(out, kSecPublicKeyAttrs);
    CHECK("public sub-dict still present", outSub != NULL);
    CHECK("public sub-dict access group removed", !CFDictionaryContainsKey(outSub, kSecAttrAccessGroup));

    if (c) CFRelease(out);
    CFRelease(sub);
    CFRelease(in);
}

static void test_strip_top_and_subdict_together(void) {
    printf("test_strip_top_and_subdict_together\n");
    const void *subKeys[] = { kSecAttrAccessGroup };
    const void *subVals[] = { CFSTR("inner") };
    CFDictionaryRef sub = MakeDict(1, subKeys, subVals);

    const void *keys[] = { kSecAttrAccessGroup, kSecPrivateKeyAttrs };
    const void *vals[] = { CFSTR("outer"), sub };
    CFDictionaryRef in = MakeDict(2, keys, vals);

    bool c = false;
    CFDictionaryRef out = HyniSignCopyStripped(in, &c);
    CHECK("didCopy=true with access group at both levels", c == true);
    CHECK("top-level access group removed", !CFDictionaryContainsKey(out, kSecAttrAccessGroup));

    CFDictionaryRef outSub = (CFDictionaryRef)CFDictionaryGetValue(out, kSecPrivateKeyAttrs);
    CHECK("sub-dict access group removed", !CFDictionaryContainsKey(outSub, kSecAttrAccessGroup));

    if (c) CFRelease(out);
    CFRelease(sub);
    CFRelease(in);
}

static void test_does_not_mutate_input(void) {
    printf("test_does_not_mutate_input\n");
    const void *keys[] = { kSecAttrAccessGroup };
    const void *vals[] = { CFSTR("group.id") };
    CFDictionaryRef in = MakeDict(1, keys, vals);

    bool c = false;
    CFDictionaryRef out = HyniSignCopyStripped(in, &c);
    CHECK("input dict still has access group (input not mutated)",
          CFDictionaryContainsKey(in, kSecAttrAccessGroup));

    if (c) CFRelease(out);
    CFRelease(in);
}

static void test_didcopy_pointer_optional(void) {
    printf("test_didcopy_pointer_optional\n");
    const void *keys[] = { kSecAttrAccessGroup };
    const void *vals[] = { CFSTR("group.id") };
    CFDictionaryRef in = MakeDict(1, keys, vals);

    // NULL didCopy must not crash.
    CFDictionaryRef out = HyniSignCopyStripped(in, NULL);
    CHECK("NULL didCopy produces a stripped output", out != in);
    CHECK("NULL didCopy: output has no access group", !CFDictionaryContainsKey(out, kSecAttrAccessGroup));

    if (out != in) CFRelease(out);
    CFRelease(in);
}

int main(void) {
    test_null_input();
    test_passthrough_when_no_access_group();
    test_strip_top_level();
    test_strip_private_key_attrs_subdict();
    test_strip_public_key_attrs_subdict();
    test_strip_top_and_subdict_together();
    test_does_not_mutate_input();
    test_didcopy_pointer_optional();

    printf("\n%d passed, %d failed\n", passed, failed);
    return failed > 0 ? 1 : 0;
}
