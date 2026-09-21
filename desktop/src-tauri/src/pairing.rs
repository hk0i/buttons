//! Device identity, one-time pairing token, and the persisted pairing slot
//! (`device.json`). Exposes the single validator both first-pair and
//! reconnect route through — see
//! docs/slices/07. Discovery, Pairing & Config Sync.spec.md, Implementation
//! Notes #1-4.

use serde::{Deserialize, Serialize};
use std::fs;
use std::path::PathBuf;
use std::sync::Mutex;
use std::time::{Duration, Instant, SystemTime, UNIX_EPOCH};
use uuid::Uuid;

/// Bumped on any breaking wire change. Checked before the token validator
/// runs — see slice 07 spec, § Implementation Notes, "`protocol_version`
/// is checked, not just carried."
pub const PROTOCOL_VERSION: &str = "1";

/// From the moment the QR is (re)rendered, not from server start.
const ONE_TIME_TOKEN_TTL: Duration = Duration::from_secs(90);

#[derive(Serialize, Deserialize)]
pub struct PairedSlot {
    pub auth_token: String,
    pub paired_at: String,
}

/// Bonjour's own instance-label limit — see
/// docs/slices/07c. Desktop Device Name.spec.md, Scope → In item 2.
/// Enforced here at the point of writing, not discovered later as a
/// silent truncation elsewhere.
const DEVICE_NAME_MAX_BYTES: usize = 63;

/// On-disk shape of `device.json` — this desktop's identity plus its
/// current pairing credential, if any.
#[derive(Serialize, Deserialize)]
struct DeviceFile {
    device_id: String,
    /// `default`, not required — avoids a crash loading a device.json
    /// from before this field existed.
    #[serde(default = "default_device_name")]
    device_name: String,
    paired: Option<PairedSlot>,
}

/// Truncates to at most `DEVICE_NAME_MAX_BYTES` UTF-8 bytes without
/// splitting a multi-byte codepoint.
fn truncate_device_name(name: &str) -> String {
    if name.len() <= DEVICE_NAME_MAX_BYTES {
        return name.to_string();
    }
    let mut end = DEVICE_NAME_MAX_BYTES;
    while !name.is_char_boundary(end) {
        end -= 1;
    }
    name[..end].to_string()
}

/// Hostname fallback, shared by a fresh `device.json` and by
/// `#[serde(default)]` on load.
fn default_device_name() -> String {
    truncate_device_name(
        &hostname::get()
            .ok()
            .and_then(|h| h.into_string().ok())
            .unwrap_or_else(|| "Buttons Desktop".to_string()),
    )
}

struct OneTimeToken {
    token: String,
    issued_at: Instant,
}

pub struct Pairing {
    device_path: PathBuf,
    device: Mutex<DeviceFile>,
    one_time: Mutex<Option<OneTimeToken>>,
}

impl Pairing {
    /// Loads `device.json`, generating a new `device_id` (and writing the
    /// file) on first launch that finds none. `device_id` never changes
    /// once generated — mobile's reconnect matching depends on that
    /// stability. Lives beside `buttons.json`, same directory — caller
    /// passes that path.
    pub fn load_or_create(device_path: PathBuf) -> Result<Self, String> {
        let device = if device_path.exists() {
            let data = fs::read_to_string(&device_path).map_err(|e| e.to_string())?;
            serde_json::from_str(&data).map_err(|e| e.to_string())?
        } else {
            let fresh = DeviceFile {
                device_id: Uuid::new_v4().to_string(),
                device_name: default_device_name(),
                paired: None,
            };
            let data = serde_json::to_string_pretty(&fresh).map_err(|e| e.to_string())?;
            fs::write(&device_path, data).map_err(|e| e.to_string())?;
            fresh
        };
        Ok(Self {
            device_path,
            device: Mutex::new(device),
            one_time: Mutex::new(None),
        })
    }

    pub fn device_id(&self) -> String {
        self.device.lock().unwrap().device_id.clone()
    }

    pub fn device_name(&self) -> String {
        self.device.lock().unwrap().device_name.clone()
    }

    /// Persists a new name, capped at `DEVICE_NAME_MAX_BYTES`. `device_id`
    /// is untouched — renaming never affects reconnect matching.
    pub fn set_device_name(&self, name: String) -> Result<(), String> {
        let name = truncate_device_name(&name);
        let mut device = self.device.lock().unwrap();
        device.device_name = name;
        let data = serde_json::to_string_pretty(&*device).map_err(|e| e.to_string())?;
        fs::write(&self.device_path, data).map_err(|e| e.to_string())
    }

    /// Issues a fresh one-time token, discarding whatever was live before
    /// — a screenshot of an old QR stops working the moment a new one is
    /// requested (DoD 8), independent of the TTL expiring on its own
    /// (DoD 9).
    pub fn issue_pairing_token(&self) -> String {
        let token = Uuid::new_v4().to_string();
        *self.one_time.lock().unwrap() = Some(OneTimeToken {
            token: token.clone(),
            issued_at: Instant::now(),
        });
        token
    }

    /// Remaining validity of the live one-time token, if any — for the
    /// pairing UI's "expires in ~90s" / expired-state rendering.
    pub fn pairing_token_remaining(&self) -> Option<Duration> {
        let guard = self.one_time.lock().unwrap();
        let ott = guard.as_ref()?;
        ONE_TIME_TOKEN_TTL.checked_sub(ott.issued_at.elapsed())
    }

    /// The one validator both first-pair and reconnect route through —
    /// same code path either way, the caller doesn't need to know which
    /// case it is. Returns the `auth_token` to send back in `PairResponse`
    /// on success. A fresh one-time-token pair mints and persists a new
    /// `auth_token`; a reconnect returns the existing one unchanged — no
    /// rotation, v1 (slice 07 spec, § Scope → Out, "Token rotation").
    pub fn validate(&self, token: &str) -> Option<String> {
        {
            let mut guard = self.one_time.lock().unwrap();
            if let Some(ott) = guard.as_ref() {
                let fresh = ott.issued_at.elapsed() < ONE_TIME_TOKEN_TTL;
                if fresh && ott.token == token {
                    *guard = None; // one-time: consumed, can't be replayed
                    drop(guard);
                    return Some(self.mint_and_persist_auth_token());
                }
            }
        }

        let device = self.device.lock().unwrap();
        device
            .paired
            .as_ref()
            .filter(|p| p.auth_token == token)
            .map(|p| p.auth_token.clone())
    }

    fn mint_and_persist_auth_token(&self) -> String {
        let auth_token = Uuid::new_v4().to_string();
        let paired_at = SystemTime::now()
            .duration_since(UNIX_EPOCH)
            .unwrap()
            .as_secs()
            .to_string();

        let mut device = self.device.lock().unwrap();
        device.paired = Some(PairedSlot {
            auth_token: auth_token.clone(),
            paired_at,
        });
        // Best-effort persist; an in-memory pair still works for this
        // session even if the write fails (e.g. disk full) — logged, not
        // fatal, per EDD §7's "minimum bar is local logging."
        match serde_json::to_string_pretty(&*device) {
            Ok(data) => {
                if let Err(e) = fs::write(&self.device_path, data) {
                    eprintln!("pairing: failed to persist device.json: {e}");
                }
            }
            Err(e) => eprintln!("pairing: failed to serialize device.json: {e}"),
        }
        auth_token
    }
}

/// Checked before `Pairing::validate` runs — a mismatch is rejected through
/// the same `PairResponse{ok:false, error}` path, not silently ignored.
/// This slice is the only version that will ever exist, so it can't be
/// exercised end-to-end yet, but it must be wired now (Implementation
/// Notes #2).
pub fn check_protocol_version(v: &str) -> bool {
    v == PROTOCOL_VERSION
}

#[cfg(test)]
mod tests {
    use super::*;

    // 90s TTL expiry itself is covered by the slice's manual DoD walk
    // (item 9) — not worth a sleeping unit test here.

    fn temp_device_path(name: &str) -> PathBuf {
        std::env::temp_dir().join(format!("buttons-pairing-test-{name}-{}.json", Uuid::new_v4()))
    }

    #[test]
    fn generates_and_persists_device_id_once() {
        let path = temp_device_path("device-id");
        let id1 = Pairing::load_or_create(path.clone()).unwrap().device_id();
        let id2 = Pairing::load_or_create(path.clone()).unwrap().device_id();
        assert_eq!(id1, id2);
        fs::remove_file(&path).ok();
    }

    #[test]
    fn fresh_one_time_token_validates_and_mints_persistent_auth_token() {
        let path = temp_device_path("fresh-pair");
        let p = Pairing::load_or_create(path.clone()).unwrap();
        let token = p.issue_pairing_token();
        let auth = p.validate(&token).expect("valid one-time token should pair");
        // reconnect with the minted auth_token succeeds, same value
        assert_eq!(p.validate(&auth), Some(auth.clone()));
        fs::remove_file(&path).ok();
    }

    #[test]
    fn one_time_token_is_single_use() {
        let path = temp_device_path("single-use");
        let p = Pairing::load_or_create(path.clone()).unwrap();
        let token = p.issue_pairing_token();
        assert!(p.validate(&token).is_some());
        assert!(
            p.validate(&token).is_none(),
            "replaying a consumed one-time token must fail"
        );
        fs::remove_file(&path).ok();
    }

    #[test]
    fn issuing_a_new_token_invalidates_the_old_one() {
        let path = temp_device_path("regenerate");
        let p = Pairing::load_or_create(path.clone()).unwrap();
        let old = p.issue_pairing_token();
        let _new = p.issue_pairing_token();
        assert!(p.validate(&old).is_none());
        fs::remove_file(&path).ok();
    }

    #[test]
    fn unknown_token_does_not_validate() {
        let path = temp_device_path("unknown");
        let p = Pairing::load_or_create(path.clone()).unwrap();
        assert!(p.validate("garbage").is_none());
        fs::remove_file(&path).ok();
    }

    #[test]
    fn protocol_version_check() {
        assert!(check_protocol_version(PROTOCOL_VERSION));
        assert!(!check_protocol_version("2"));
    }

    #[test]
    fn loads_a_pre_existing_device_json_missing_device_name_without_panicking() {
        // Regression: an old device.json with no device_name must still load.
        let path = temp_device_path("pre-existing-shape");
        fs::write(&path, r#"{"device_id":"abc-123","paired":null}"#).unwrap();
        let p = Pairing::load_or_create(path.clone()).unwrap();
        assert_eq!(p.device_id(), "abc-123");
        assert!(!p.device_name().is_empty());
        fs::remove_file(&path).ok();
    }

    #[test]
    fn fresh_device_defaults_to_a_nonempty_name() {
        let path = temp_device_path("default-name");
        let p = Pairing::load_or_create(path.clone()).unwrap();
        assert!(!p.device_name().is_empty());
        fs::remove_file(&path).ok();
    }

    #[test]
    fn set_device_name_persists_across_reload() {
        let path = temp_device_path("rename");
        {
            let p = Pairing::load_or_create(path.clone()).unwrap();
            p.set_device_name("Greg's Mac Mini".to_string()).unwrap();
        }
        let reloaded = Pairing::load_or_create(path.clone()).unwrap();
        assert_eq!(reloaded.device_name(), "Greg's Mac Mini");
        fs::remove_file(&path).ok();
    }

    #[test]
    fn set_device_name_truncates_at_63_bytes_without_splitting_a_codepoint() {
        let path = temp_device_path("truncate");
        let p = Pairing::load_or_create(path.clone()).unwrap();
        // multi-byte codepoints throughout, well past the 63-byte cap
        let long_name: String = std::iter::repeat('🎉').take(40).collect();
        p.set_device_name(long_name).unwrap();
        assert!(p.device_name().len() <= DEVICE_NAME_MAX_BYTES);
        fs::remove_file(&path).ok();
    }
}
