# Task Completion

After any coding change, run:

```bash
cd KhVolume && swift test
```

No linter or formatter is configured (no SwiftLint/SwiftFormat in the project).

For changes to the Python helper (`KhVolume/Helper/`), rebuild it before testing the full app:

```bash
./scripts/build-khvol-helper.sh
```

For hardware-dependent behaviour, use the smoke test (requires `KHVOL_INTERFACE` set to a real interface):

```bash
export KHVOL_INTERFACE=en15
./scripts/smoke-test.sh
```
