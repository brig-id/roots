# helpers4 (Rust) — adoption and extraction candidates

Survey of `cli`, `crypto`, `core` and `server-leaf` against
[`helpers4` 0.0.1](https://crates.io/crates/helpers4) (features: `array`, `env`, `hex`, `string`).
`helpers4` is LGPL-3.0-or-later, the same as our crates, and `deny.toml` already allows that
license.

## 1. Code we can already replace with helpers4

| Where | Today | helpers4 | Notes |
| ----- | ----- | -------- | ----- |
| `cli/src/env_file.rs` — `read_master_key` | Manual loop over `lines()` + `strip_prefix` | `env::get` | Also handles quotes and comments. |
| `cli/src/env_file.rs` — `write_master_key` | Filter + push + `join` | `env::set` | Replaces in place (keeps line order and endings), validates the key name. |
| `cli/src/env_file.rs` — `generate_master_key` | `format!("{b:02x}")` collected per byte | `hex::encode` | One allocation instead of one per byte. |
| `crypto/src/master_key.rs` — `from_hex` | `hex::decode_to_slice` | `hex::decode_to_slice` | Drops the `hex` dependency. `error.rs` `HexDecode(#[from] hex::FromHexError)` becomes `helpers4::hex::DecodeError`. |
| `core/crates/brigid-store/src/store.rs` — `username_index` | `hex::encode(*key)` | `hex::encode` | Drops the `hex` dependency. |

Points to check in `crypto`:
- `Error::HexDecode` is public API. Changing its payload type is a breaking change for anyone
  matching on it (semver-minor on 0.x, but worth a CHANGELOG line).
- `helpers4::hex::DecodeError::InvalidChar` carries the offending character and its index, like
  `hex::FromHexError`. The manual `Debug` on our `Error` still redacts it, so the leak protection
  in `crypto/src/error.rs` and its `from_hex_error_debug_does_not_leak_input` test keep working.
- The 64-char length check in `from_hex` stays; `decode_to_slice` also checks length.

No current use of `array` or `string` helpers was found. There is no case conversion, slugging,
truncation, HTML escaping, `group_by` or dedup in these repos yet.

## 2. Candidates to externalize into helpers4

General-purpose, pure or near-pure, no brig·id domain knowledge. Ordered by value.

### 2.1 `net::is_public_ip` / `net::is_disallowed_target` — strong
- **Source:** `core/crates/brigid-did/src/web.rs` (`is_disallowed_target`).
- **What it does:** SSRF guard. Rejects loopback, private, link-local (cloud metadata), unspecified,
  multicast, broadcast, documentation, IPv6 unique-local and link-local, and unwraps IPv4-mapped and
  IPv4-compatible IPv6 before checking.
- **Why it belongs in helpers4:** self-contained, only uses `std::net`, and easy to get wrong. The
  `::1` → `0.0.0.1` pitfall documented in the code is a good example.
- **Extraction:** rename to a positive predicate (`is_public_ip(IpAddr) -> bool`) and move the
  existing tests (loopback, private ranges, metadata, ULA, mapped/compatible v6) with it.

### 2.2 `net::is_valid_hostname` — strong
- **Source:** `core/crates/brigid-identity/src/root_id.rs` (`validate_server`).
- **What it does:** RFC 1035/1123 hostname validation: total ≤ 253 octets (optional trailing dot),
  labels 1–63 octets, `[A-Za-z0-9-]`, no leading or trailing hyphen.
- **Extraction:** return `Result<(), HostnameError>` with an enum (`Empty`, `TooLong`,
  `EmptyLabel`, `LabelTooLong`, `InvalidChar`, `HyphenEdge`); we map it to
  `Error::InvalidIdentifier` locally. The 7 existing `server_*` tests move as-is.
- **Stays in brig·id:** `validate_username` (3–64 chars, not only `_`) is a product rule.

### 2.3 `http::bearer_token` — medium
- **Source:** `core/crates/brigid-api/src/middleware.rs` (`extract_bearer`).
- **What it does:** strips the `Bearer ` prefix from an `Authorization` header value.
- **Extraction:** keep it `&str`-based (`bearer_token(&str) -> Option<&str>`) so helpers4 needs no
  `http` dependency. RFC 7235 makes the scheme case-insensitive, whereas ours is case-sensitive.
  Decide whether to match the RFC; it is a small behavior change on our side.

### 2.4 `collections::ExpiringSet` / `ExpiringMap` — medium
- **Sources:** `core/crates/brigid-oidc/src/jti.rs` (`JtiStore`: map of key → expiry, evict on every
  insert, replay check) and `core/crates/brigid-api/src/state.rs` (`evict_expired_pending`: `retain`
  on age for two maps).
- **Pattern:** a bounded in-memory map whose entries expire, evicted lazily on write.
- **Extraction:** generic `ExpiringMap<K, V>` with the clock injected (`now` passed in, or a
  `Clock` trait) so it is testable without sleeping. `check_and_insert` becomes `insert_if_absent`.
- **Stays in brig·id:** `JtiStore` itself (`Error::JtiReplay`, persistence model in `brigid-store`)
  becomes a thin wrapper.

### 2.5 `sync::lock_or_recover` — small
- **Pattern:** `mutex.lock().unwrap_or_else(|e| e.into_inner())` appears 11 times across `core`,
  `server-leaf` and `crypto`.
- **Extraction:** a small `Mutex`/`RwLock` extension trait. Whether it is a good default (recovering
  from a poisoned lock) is a policy call; worth documenting in the helper.

### 2.6 `time::unix_now` — small
- **Pattern:** `SystemTime::now().duration_since(UNIX_EPOCH).unwrap_or_default().as_secs()`,
  written out in `jti.rs`, `token.rs` and `store.rs` (twice).
- **Extraction:** `unix_now() -> i64` (and maybe `unix_now_ms`). Trivial, but it removes the
  copy-paste. Only worth it if helpers4 wants a `time` module.

### 2.7 `env::var_os_zeroizing` — niche, probably not
- **Source:** `crypto/src/master_key.rs` (`os_string_into_zeroizing_string`).
- **Why it is on the fence:** general enough (read an env var as `Zeroizing<String>` without leaving
  an unwiped copy on the non-UTF-8 path), but it uses `unsafe` and depends on `zeroize`. It is
  security-critical and fits better in a dedicated crate than in a general-purpose helpers crate.
  Keep it in `crypto` unless helpers4 grows a `secret` feature.

## 3. Not candidates (domain-specific)

`derive_*`/`compute_vsid`/`username_index` (crypto and identity rules), `did:*` build/resolve,
`issue_token`/`validate_token`, the store API, `rotate_master_key`, `validate_username`, and the
`cli` repo-orchestration helpers (`repos.rs`, `has_pnpm_script`, `kind`).

## 4. Suggested order

1. Adopt `hex` and `env` in `cli`, `crypto`, `core` (section 1). No new code, drops two dependencies.
2. Extract 2.1 and 2.2 to helpers4, then use them from `core`.
3. Decide on 2.3, 2.4, 2.5 and 2.6 depending on the scope helpers4 wants.
