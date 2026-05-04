#include "access_group.h"
#include <Security/Security.h>

CFDictionaryRef HyniSignCopyStripped(CFDictionaryRef in, bool *didCopy) {
    if (didCopy) *didCopy = false;
    if (!in) return in;

    bool topNeeds = CFDictionaryContainsKey(in, kSecAttrAccessGroup);
    CFDictionaryRef priv = (CFDictionaryRef)CFDictionaryGetValue(in, kSecPrivateKeyAttrs);
    CFDictionaryRef pub  = (CFDictionaryRef)CFDictionaryGetValue(in, kSecPublicKeyAttrs);
    bool privNeeds = priv && CFDictionaryContainsKey(priv, kSecAttrAccessGroup);
    bool pubNeeds  = pub  && CFDictionaryContainsKey(pub,  kSecAttrAccessGroup);

    if (!topNeeds && !privNeeds && !pubNeeds) return in;

    CFMutableDictionaryRef out = CFDictionaryCreateMutableCopy(NULL, 0, in);
    if (topNeeds) CFDictionaryRemoveValue(out, kSecAttrAccessGroup);

    if (privNeeds) {
        CFMutableDictionaryRef sub = CFDictionaryCreateMutableCopy(NULL, 0, priv);
        CFDictionaryRemoveValue(sub, kSecAttrAccessGroup);
        CFDictionarySetValue(out, kSecPrivateKeyAttrs, sub);
        CFRelease(sub);
    }
    if (pubNeeds) {
        CFMutableDictionaryRef sub = CFDictionaryCreateMutableCopy(NULL, 0, pub);
        CFDictionaryRemoveValue(sub, kSecAttrAccessGroup);
        CFDictionarySetValue(out, kSecPublicKeyAttrs, sub);
        CFRelease(sub);
    }

    if (didCopy) *didCopy = true;
    return out;
}
