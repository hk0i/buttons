//! Local-only record of which state each Switch button is currently
//! showing (`switch_state.json`), sibling to `device.json` — never part of
//! `buttons.json`/`save_config`/`get_config`, never exported. The one place
//! "which state is this Switch showing right now" lives durably. See
//! slice 09 spec, § Scope → In #3 and Implementation Notes #2.

use crate::server::{StateChange, StatePushTx};
use std::collections::HashMap;
use std::fs;
use std::path::Path;
use std::sync::{Arc, Mutex};

/// button_id -> is "on" showing. Loaded once at launch, saved after every
/// successful flip (`server.rs`'s real `ButtonPress` handler, `lib.rs`'s
/// `test_button` command). `Mutex`, not a `watch`/`RwLock` — writes are
/// rare (a press or a `Test` click) and reads happen once per
/// `config_sync`; no contention this design needs to optimize for. See
/// slice 09 spec, § Interface Note 5.
pub type SwitchStates = Arc<Mutex<HashMap<String, bool>>>;

/// Loads `switch_state.json`, or an empty map if it doesn't exist yet — a
/// button with no recorded press yet is `off`, matching the map's own
/// absent-key default (slice 09 spec, § Interface Note 1).
pub fn load(switch_state_path: &Path) -> SwitchStates {
    let map = if switch_state_path.exists() {
        fs::read_to_string(switch_state_path)
            .ok()
            .and_then(|data| serde_json::from_str(&data).ok())
            .unwrap_or_default()
    } else {
        HashMap::new()
    };
    Arc::new(Mutex::new(map))
}

/// Persists the current map. Best-effort — logged, not fatal, matching
/// `pairing.rs`'s `device.json` write (EDD §7's "minimum bar is local
/// logging").
pub fn save(switch_state_path: &Path, states: &SwitchStates) {
    let map = states.lock().unwrap();
    match serde_json::to_string_pretty(&*map) {
        Ok(data) => {
            if let Err(e) = fs::write(switch_state_path, data) {
                eprintln!("switch_state: failed to persist switch_state.json: {e}");
            }
        }
        Err(e) => eprintln!("switch_state: failed to serialize switch_state.json: {e}"),
    }
}

/// Records a successful flip, persists it, and broadcasts the change —
/// the only way `switch_state.json` changes, and the one shared exit for
/// every flip regardless of what triggered it (a real `ButtonPress` or the
/// editor's `Test`). See slice 09a spec, § Scope → In #3. Two sequential
/// lock scopes, not one nested call: `save` takes its own lock, and
/// `Mutex` isn't reentrant, so the write must fully release the guard
/// before `save` acquires it again.
pub fn flip_and_save(
    switch_state_path: &Path,
    states: &SwitchStates,
    button_id: &str,
    new_value: bool,
    state_push_tx: &StatePushTx,
) {
    {
        let mut map = states.lock().unwrap();
        map.insert(button_id.to_string(), new_value);
    }
    save(switch_state_path, states);
    // Send if anyone's listening, ignore if not — `send` errors only when
    // there are zero subscribers (no connection open), a normal state, not
    // a fault to log or retry. See slice 09a spec, § Implementation Notes 2.
    let _ = state_push_tx.send(vec![StateChange {
        button_id: button_id.to_string(),
        is_active: new_value,
    }]);
}
