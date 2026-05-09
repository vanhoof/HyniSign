# HyniSign

Restores Microsoft / Xbox Live sign-in for sideloaded Minecraft: Bedrock Edition on non-jailbroken iOS / iPadOS.

Designed to be injected alongside [HynisLoader](https://github.com/congcq/HynisLoader)'s `libhynisloader.dylib` so you can run RenderDragon shader packs **and** sign into your Microsoft account on the same install.

## The problem

On a sideloaded Minecraft IPA (e.g., re-signed with Sideloadly + a free Apple Developer cert), tapping **Sign in** produces an in-game error:

> Failed to login. We could not sign you into your Microsoft account…
> Error Code **Drowned**

The actual root cause shows up in `Console.app` as:

```
SecKeyCreateRandomKey failed: Error Domain=NSOSStatusErrorDomain Code=-34018
"failed to add key to keychain..."
```

`-34018` is `errSecMissingEntitlement`. When Sideloadly re-signs, the `keychain-access-groups` entitlement gets re-derived to your team ID — the original Mojang access group becomes unreachable. Microsoft's bundled `Xal.framework` (Xbox Authentication Library) tries to look up its device-identity ECDSA key in that original group, fails, and aborts the auth flow before the OAuth web sheet ever opens.

## What this fix does

A small dylib that uses [fishhook](https://github.com/facebook/fishhook) to rebind the Security.framework symbols imported by Minecraft's binary and `Xal.framework`. Each call to `SecItemAdd` / `SecItemCopyMatching` / `SecItemUpdate` / `SecItemDelete` / `SecKeyCreateRandomKey` / `SecKeyGeneratePair` has its `kSecAttrAccessGroup` attribute stripped before being forwarded to the real implementation. Keychain then falls back to the app's actual entitlement — which the re-signed cert legitimately has — and Xal finds (or generates) its key, OAuth proceeds, and you're signed in.

## Compatibility

| | |
|---|---|
| **Tested on** | iPadOS 26.4.2, iPad with Apple Silicon |
| **Game version** | Minecraft: Bedrock Edition 1.26.13 |
| **Sideloader** | Sideloadly (free Apple ID) |
| **Architecture** | arm64 |

Should work on other iOS / iPadOS versions in roughly the same generation. Earlier iOS versions where TrollStore is still viable don't need this fix — TrollStore preserves entitlements.

## What this does NOT do

- **Does not bypass App Attest / DeviceCheck.** Microsoft doesn't require those for the Xbox Live iOS sign-in path at the time of writing. If they add it, this fix won't be enough on its own.
- **Does not sign or install the IPA.** That's Sideloadly's job.
- **Does not provide the patched Minecraft IPA.** You need a base IPA already injected with HynisLoader's `libhynisloader.dylib`. This repo only adds the auth fix on top.

## Build

Requires:
- macOS with Xcode Command Line Tools
- [Theos](https://theos.dev/) installed and `$THEOS` in your shell

```sh
git clone https://github.com/vanhoof/HyniSign
cd HyniSign
make
```

Output: `build/HyniSign.dylib`. The dylib uses `@executable_path` install names and is ad-hoc signed; Sideloadly will re-sign it with your cert when injecting.

Build flags:
- `make HYNISIGN_VERBOSE=1` — log every intercepted keychain call (off by default; default only logs the rare stripping events)

If you'd rather not build it yourself, prebuilt `HyniSign.dylib` artifacts are attached to each [GitHub Release](../../releases). Tagged commits (`v*`) automatically build, test, and publish via CI.

## Tests

Two layers of tests run in CI and can be run locally.

**Unit tests** for the access-group stripping logic (pure C, builds on macOS host with `clang`, links against the same `access_group.c` that ships in the dylib):

```sh
make -C tests test
```

**Build smoke tests** for the produced iOS dylib — verify architecture (arm64-only), `@executable_path` install name, framework dependencies (Foundation, CoreFoundation, Security), absence of CydiaSubstrate, and presence of all expected wrapper symbols and rebound symbol-name strings:

```sh
make                        # build the dylib first
bash tests/check-build.sh   # then verify it
```

## Install

1. Open **Sideloadly** on your Mac (or Windows).
2. Plug in your iPad / iPhone, trust the computer.
3. **Make sure your IPA contains both `libhynisloader.dylib` (HynisLoader) and `HyniSign.dylib` (this project).** Two ways to set that up:
   - **Bundle at patch time** — include `build/HyniSign.dylib` alongside `libhynisloader.dylib` when you patch the Minecraft IPA with HynisLoader's tooling. Both dylibs end up inside the IPA before you ever hand it to Sideloadly.
   - **Inject at sign time** — start with a HynisLoader-only IPA (just `libhynisloader.dylib` inside) and let Sideloadly add `HyniSign.dylib` via its **Inject dylibs/deb/bundle** option (step 5 below).

   Either path works; the resulting installed app is identical. If you already have a HynisLoader-only IPA and don't want to re-pack it, take the inject-at-sign-time path.
4. Drag the IPA onto the Sideloadly window. Click the **gear icon → Advanced options**.
5. *(Inject-at-sign-time path only)* Under **Inject dylibs/deb/bundle**, add `build/HyniSign.dylib`.
6. **Keep the same bundle ID** across re-signings (changing it would break Microsoft's OAuth redirect URL scheme separately from this fix).
7. Enter your Apple ID and start. Trust the developer cert in *Settings → General → VPN & Device Management* on the device.

## Verify it's working

1. Plug iPad into Mac, open **Console.app**, select the iPad, filter `process:minecraftpe`, start streaming.
2. Launch Minecraft. You should see, near the top:

   ```
   [HyniSign] loading
   [HyniSign] rebind_symbols returned 0, hooks installed
   ```

3. Tap **Sign in**. Look for at least one line like:

   ```
   [HyniSign] SecItemCopyMatching stripped, status=0
   ```

   That's the diagnostic line that proves the fix kicked in. The OAuth web sheet should open shortly after, and you should be able to sign in normally.

## Troubleshooting

- **No `[HyniSign]` lines in Console at all.** The dylib didn't load — Sideloadly's "Inject dylibs" step didn't take, or the load command isn't pointing at the right path. Re-check the inject list and re-sign.
- **`rebind_symbols returned 0` but no `SecItem*` lines fire even when tapping Sign in.** fishhook didn't catch the import table for the framework that's calling Security APIs. Identify the offending image and add it to fishhook's per-image rebinding (see "How it works" below).
- **Still `SecKeyCreateRandomKey failed: ... -34018` after install.** Likely a Minecraft / Xal update introduced a new keychain symbol we don't hook. Run `nm -u Payload/minecraftpe.app/Frameworks/Xal.framework/Xal | grep -iE '_SecKey|_SecItem'` against the new IPA, compare to the `rebs[]` array in `Tweak.x`, and add wrappers for any new symbols.
- **Sign-in fails with HTTP 401/403 from `xboxlive.com` after local crypto succeeds.** That's server-side rejection, not a keychain issue — likely Microsoft has added App Attest / DeviceCheck on the iOS auth path. This fix can't address that.

## How it works

We can't use `MSHookFunction` (CydiaSubstrate-style inline patching) on modern iOS — system framework code pages are write-protected and pointer-authentication-signed (PAC). The patch silently fails to take effect. Instead we use fishhook, which rewrites the lazy-binding pointer slots (`__DATA,__la_symbol_ptr` and `__DATA,__got`) in *our* process's loaded images. No system code is modified; the dynamic linker's normal lookup path now resolves `SecItemAdd` (and friends) to our wrappers, which mutate the parameter dictionary and call through to the real implementation.

The actual consumer that matters is `Xal.framework` (Microsoft's Xbox Authentication Library, bundled inside the Minecraft IPA). On Minecraft Bedrock 1.26.13, Xal imports `_SecItemAdd`, `_SecItemCopyMatching`, `_SecItemDelete`, and `_SecKeyGeneratePair`. The first call to `SecItemCopyMatching` during sign-in is what fails on a re-signed binary, because the query carries Mojang's original `kSecAttrAccessGroup` value. Strip that one attribute and the lookup succeeds (or returns "not found," which is fine — Xal then generates a fresh keypair, which we also intercept). Either path leads to the OAuth web sheet opening normally.

We do *not* hook `dlsym`, even though Xal imports it. As of this writing, none of the relevant `Sec*` calls go through `dlsym` — they all use ordinary lazy binding. If a future build moves them, the fix is to also hook `dlsym` and substitute our wrapper when it's asked for one of the targeted symbols.

The fix explicitly does not bypass App Attest / DeviceCheck. Those would require an Apple-issued attestation that only Mojang's signing identity can produce, and no client-side dylib can fake one. We're relying on the Xbox Live iOS endpoints not requiring attestation today; if that changes, this fix won't be sufficient on its own.

## Acknowledgments

- [HynisLoader](https://github.com/congcq/HynisLoader) by congcq — the upstream RenderDragon shader-loading dylib (`libhynisloader.dylib`) this fix is meant to coexist with.
- [fishhook](https://github.com/facebook/fishhook) by Facebook — the symbol-rebinding library that makes this hook work on non-jailbroken iOS. Vendored into this repo as `fishhook.c` / `fishhook.h`.

## License

MIT for the HyniSign code in this repository.
fishhook is BSD-licensed; see the header in `fishhook.c`.
