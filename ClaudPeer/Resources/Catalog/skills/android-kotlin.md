# Android Kotlin (Jetpack Compose)

## When to Activate

Use when shipping Compose UI, handling lifecycle/process death, or hardening storage across OEMs. Apply for new features, Material 3 theming, and performance reviews.

## Process

1. **Single source of truth**: Hold UI state in `ViewModel` + `UiState` data class; expose `StateFlow`/`Flow` collected with `collectAsStateWithLifecycle` in composables—never duplicate truth in composable locals for async data.
2. **Lifecycle-aware collection**: Use `repeatOnLifecycle(Lifecycle.State.STARTED)` in fragments/activities when not using Compose-only entry points to avoid leaks and wasted work.
3. **Configuration changes**: Use `rememberSaveable` for transient UI; persist critical ids via **`SavedStateHandle`**. Test rotation and **Don’t keep activities**.
4. **Process death**: Assume process kill after backgrounding; restore from `SavedState` + repository, not memory-only singletons.
5. **Main thread**: Offload disk/network with **`Dispatchers.IO`** or **`withContext`**; use **StrictMode** in debug builds to catch accidental main-thread IO.
6. **Structured concurrency**: Scope coroutines to lifecycle (`viewModelScope`, `lifecycleScope`); cancel child jobs on stop. Prefer **`suspend`** APIs over callback hell.
7. **Security**: Use **EncryptedSharedPreferences** or **Android Keystore** for tokens; disable backups for sensitive files via `android:fullBackupContent` rules.
8. **Fragmentation**: Test multiple API levels and OEMs (Samsung, Xiaomi) for back gesture, permissions, and display cutouts.

## Checklist

- [ ] ViewModel owns screen state; composables are stateless where possible
- [ ] Flows collected with lifecycle awareness
- [ ] Rotation/process death tested
- [ ] No blocking work on main thread
- [ ] Secrets in encrypted/keystore storage
- [ ] Tested on low-RAM emulator + one OEM device

## Tips

Enable **R8** full mode in release. Use **Macrobenchmark** for startup and **Layout Inspector** for recomposition counts. Follow **Material 3** motion and shape tokens.
