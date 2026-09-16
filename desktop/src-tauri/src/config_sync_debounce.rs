//! Coalesces `save_config` edits into one `config_sync` resync signal. See
//! slice 09c spec, § Files to Touch #2.

use crate::config;
use crate::server;

/// Stacked on top of ButtonEditor's own 500ms autosave debounce. See slice
/// 09c spec, § Interface Note 3.
const QUIET_PERIOD: std::time::Duration = std::time::Duration::from_millis(1000);

/// Trailing-edge coalesce, dirty-checked against the last `Config`
/// broadcast. `last_sent` seeds from disk at startup so the first ping
/// after launch doesn't unconditionally fire. See slice 09c spec, §
/// Implementation Notes #2-3.
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
                Ok(Some(next)) => latest = next, // re-armed, keep newest
                Ok(None) => return,               // shutting down
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
