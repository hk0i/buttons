//! Coalesces `save_config` edits into a single `config_sync` resync signal.
//! A separate module from `switch_state.rs` deliberately — different
//! trigger (an authored edit vs. a runtime flip) and a different guard
//! (coalesce + dirty-check vs. none). See slice 09c spec, § Files to Touch
//! #2.

use crate::config;
use crate::server;

/// How long to wait after the last `save_config` ping before treating
/// edits as settled. Independent of, and stacked on top of, `ButtonEditor`'s
/// own 500ms autosave debounce (Slice 4) — total edit-to-phone latency is
/// frontend-debounce + this, roughly ≤1.5s worst case. A second, larger
/// constant here (not reusing 500ms) is deliberate: it has to absorb the
/// frontend's debounce restarting on every keystroke, not just line up
/// with it. See slice 09c spec, § Interface Note 3.
const QUIET_PERIOD: std::time::Duration = std::time::Duration::from_millis(1000);

/// Trailing-edge coalesce, no cancellation bookkeeping: block for the first
/// ping, then re-arm a fresh timeout on every ping that lands inside it;
/// only a full quiet window with no ping breaks the inner loop and fires.
/// Dirty-checked against the last `Config` actually broadcast — suppresses
/// the no-op case (see slice 09c spec, § Implementation Notes #2): opening
/// the editor on an existing button re-saves identical content and would
/// otherwise still push a redundant full-`Config` resync.
///
/// `last_sent` is seeded from disk at startup (one read, not per-ping) —
/// without this, it starts `None` and the very first ping after launch
/// broadcasts unconditionally, which is exactly the redundant resync the
/// dirty-check exists to prevent (slice 09c spec, DoD 4).
pub async fn run(
    config_path: std::path::PathBuf,
    mut dirty_rx: tokio::sync::mpsc::UnboundedReceiver<config::Config>,
    config_changed_tx: server::ConfigChangedTx,
) {
    let mut last_sent: Option<String> = config::load_config(&config_path)
        .ok()
        .and_then(|c| serde_json::to_string(&c).ok());

    while let Some(mut latest) = dirty_rx.recv().await {
        loop {
            match tokio::time::timeout(QUIET_PERIOD, dirty_rx.recv()).await {
                Ok(Some(next)) => latest = next, // re-armed, keep the newest
                Ok(None) => return,               // app shutting down
                Err(_) => break,                    // quiet elapsed
            }
        }
        let serialized = serde_json::to_string(&latest).unwrap_or_default();
        if last_sent.as_deref() != Some(serialized.as_str()) {
            last_sent = Some(serialized);
            let _ = config_changed_tx.send(());
        }
    }
}
