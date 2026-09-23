mod actions;
mod config;
mod config_sync_debounce;
mod focus_watcher;
mod mdns;
mod pairing;
mod proto;
mod server;
mod switch_state;

use config::{Action, Config};
use pairing::Pairing;
use serde::Serialize;
use std::collections::HashMap;
use std::fs;
use std::path::PathBuf;
use std::sync::Arc;
use switch_state::SwitchStates;
use tauri::{AppHandle, Manager};
use tokio::sync::broadcast;

/// Sent by `save_config` after a write; consumed by `config_sync_debounce`.
/// See slice 09c spec, § Files to Touch #3.
pub type ConfigDirtyTx = tokio::sync::mpsc::UnboundedSender<Config>;

/// Tauri-specific glue, kept out of `config.rs` so its data/persistence logic
/// stays plain Rust — reusable as-is if the UI layer ever changes.
fn config_path(app: &AppHandle) -> Result<PathBuf, String> {
    let dir = app.path().app_config_dir().map_err(|e| e.to_string())?;
    fs::create_dir_all(&dir).map_err(|e| e.to_string())?;
    Ok(dir.join("buttons.json"))
}

/// Beside `buttons.json`, same directory — genuine device-local settings
/// per EDD §5.3, not `localStorage`.
fn device_path(app: &AppHandle) -> Result<PathBuf, String> {
    let dir = app.path().app_config_dir().map_err(|e| e.to_string())?;
    fs::create_dir_all(&dir).map_err(|e| e.to_string())?;
    Ok(dir.join("device.json"))
}

/// Beside `buttons.json`/`device.json` — local-only, never part of
/// `save_config`/`get_config`. See slice 09 spec, § Scope → In #3.
fn switch_state_path(app: &AppHandle) -> Result<PathBuf, String> {
    let dir = app.path().app_config_dir().map_err(|e| e.to_string())?;
    fs::create_dir_all(&dir).map_err(|e| e.to_string())?;
    Ok(dir.join("switch_state.json"))
}

#[tauri::command]
fn get_config(app: tauri::AppHandle) -> Result<Config, String> {
    config::load_config(&config_path(&app)?)
}

/// Persists config to disk, then notifies connected devices.
#[tauri::command]
fn save_config(
    app: tauri::AppHandle,
    mut config: Config,
    dirty_tx: tauri::State<ConfigDirtyTx>,
) -> Result<(), String> {
    let path = config_path(&app)?;
    if let Ok(existing) = config::load_config(&path) {
        config::preserve_app_associations(&mut config, &existing);
    }
    config::save_config(&path, &config)?;
    let _ = dirty_tx.send(config);
    Ok(())
}

/// The dropdown's "switch to an already-existing profile" path — shares
/// `apply_profile_switch` with the OS-focus watcher's auto-switch (10a) and
/// the mobile-initiated switch, so it gets the same undebounced wire
/// announce instead of waiting on `config_sync_debounce`'s 1s quiet period.
/// Not used by create/delete-then-switch, which persist a structural
/// change to the profiles list itself via `save_config`.
#[tauri::command]
async fn switch_profile(
    app: tauri::AppHandle,
    id: String,
    dirty_tx: tauri::State<'_, ConfigDirtyTx>,
    profile_switch_tx: tauri::State<'_, server::ProfileSwitchTx>,
) -> Result<(), String> {
    let path = config_path(&app)?;
    server::apply_profile_switch(id, &path, &dirty_tx, &profile_switch_tx, &app)
        .await
        .map_err(|_| "profile switch failed".to_string())
}

#[tauri::command]
fn is_auto_switch_supported() -> bool {
    focus_watcher::is_supported()
}

#[tauri::command]
fn get_app_association(app: tauri::AppHandle, profile_id: String) -> Result<Option<String>, String> {
    let Some(platform) = config::Platform::current() else {
        return Ok(None);
    };
    let config = config::load_config(&config_path(&app)?)?;
    Ok(config
        .profiles
        .iter()
        .find(|p| p.id == profile_id)
        .and_then(|p| p.associated_app_by_platform.get(&platform).cloned()))
}

#[tauri::command]
fn set_app_association(
    app: tauri::AppHandle,
    profile_id: String,
    bundle_id: Option<String>,
    dirty_tx: tauri::State<ConfigDirtyTx>,
) -> Result<(), String> {
    let Some(platform) = config::Platform::current() else {
        return Err("auto-switch not supported on this platform".to_string());
    };
    let path = config_path(&app)?;
    let mut config = config::load_config(&path)?;
    let profile = config
        .profiles
        .iter_mut()
        .find(|p| p.id == profile_id)
        .ok_or_else(|| "profile not found".to_string())?;
    match bundle_id {
        Some(id) => {
            profile.associated_app_by_platform.insert(platform, id);
        }
        None => {
            profile.associated_app_by_platform.remove(&platform);
        }
    }
    config::save_config(&path, &config)?;
    let _ = dirty_tx.send(config);
    Ok(())
}

#[tauri::command]
fn run_actions(actions: Vec<Action>) -> Result<(), String> {
    actions::run(&actions)
}

/// Mirrors `SwitchStates` client-side — `switchStates.svelte.ts` calls this
/// once at load, then updates from the `switch-states-changed` event
/// `server::execute_press` emits after every successful flip. See slice 09
/// spec, § Files to Touch #7, #9.
#[tauri::command]
fn get_switch_states(states: tauri::State<SwitchStates>) -> HashMap<String, bool> {
    states.lock().unwrap().clone()
}

/// The editor's `Test` button. Content-type-aware: for a plain `.actions`
/// button this runs its one array, exactly as `run_actions` always has;
/// for a `.switch` button it goes through the same `execute_press` path a
/// real `ButtonPress` uses — "simulates a full real press," not a
/// separate testing-only code path that could drift from what a real
/// press actually does. See slice 09 spec, § Implementation Notes #4.
#[tauri::command]
async fn test_button(
    app: AppHandle,
    button_id: String,
    states: tauri::State<'_, SwitchStates>,
    state_push_tx: tauri::State<'_, server::StatePushTx>,
) -> Result<(), String> {
    let config_path = config_path(&app)?;
    let switch_state_path = switch_state_path(&app)?;
    server::execute_press(
        &button_id,
        &config_path,
        &switch_state_path,
        &states,
        &state_push_tx,
        &app,
    )
    .await
}

#[derive(Serialize)]
#[serde(rename_all = "camelCase")]
struct PairingQr {
    svg: String,
    payload: String,
}

#[derive(Serialize)]
#[serde(rename_all = "camelCase")]
struct RunningApp {
    bundle_id: String,
    name: String,
}

/// The picker's data source for a Profile's macOS app association (10a) —
/// empty on any other platform, since only the macOS watcher exists so far.
#[tauri::command]
async fn list_running_apps(app: tauri::AppHandle) -> Vec<RunningApp> {
    focus_watcher::running_apps(app)
        .await
        .into_iter()
        .map(|(bundle_id, name)| RunningApp { bundle_id, name })
        .collect()
}

/// Issues a fresh one-time pairing token and renders it as an SVG QR —
/// server-side (`qrcode` crate), no client-side QR library. Called each
/// time the pairing view (re)opens; the previous token is invalidated the
/// moment this runs, not left valid until its TTL expires.
#[tauri::command]
fn get_pairing_qr(pairing: tauri::State<Arc<Pairing>>) -> Result<PairingQr, String> {
    let token = pairing.issue_pairing_token();
    // "<device_id> <lan_ip> <port> <pairing_token>" — see wire.proto's
    // Interface section for why this is 4 space-delimited fields, not
    // ip:port colon-joined. Named holes, not positional `{}` — field order
    // here must match iOS's split-by-space parse; a reorder is silent
    // with positional args, not with named ones.
    let device_id = pairing.device_id();
    let ip = server::local_ip();
    let port = server::PORT;
    let payload = format!("{device_id} {ip} {port} {token}");
    let code = qrcode::QrCode::new(payload.as_bytes()).map_err(|e| e.to_string())?;
    let svg = code.render::<qrcode::render::svg::Color>().build();
    Ok(PairingQr { svg, payload })
}

/// Current persisted device name, for a settings UI to populate its field.
#[tauri::command]
fn get_device_name(pairing: tauri::State<Arc<Pairing>>) -> String {
    pairing.device_name()
}

/// Overrides the persisted device name — see
/// docs/slices/07c. Desktop Device Name.spec.md, Scope → In item 2.
#[tauri::command]
fn set_device_name(
    pairing: tauri::State<Arc<Pairing>>,
    mdns: tauri::State<Arc<mdns::Advertisement>>,
    name: String,
) -> Result<(), String> {
    pairing.set_device_name(name)?;
    mdns.rename(&pairing.device_name())
}

#[cfg_attr(mobile, tauri::mobile_entry_point)]
pub fn run() {
    tauri::Builder::default()
        .plugin(tauri_plugin_opener::init())
        .plugin(tauri_plugin_dialog::init())
        .setup(|app| {
            let handle = app.handle();
            let config_path = config_path(handle)?;
            let device_path = device_path(handle)?;
            let switch_state_path = switch_state_path(handle)?;
            let pairing = Arc::new(Pairing::load_or_create(device_path)?);
            app.manage(Arc::clone(&pairing));
            let mdns = Arc::new(mdns::Advertisement::start(pairing.device_id(), &pairing.device_name()));
            app.manage(mdns);
            let switch_states: SwitchStates = switch_state::load(&switch_state_path);
            app.manage(switch_states.clone());
            // Created once at startup, cloned into server::run and into
            // every command that can trigger a flip (test_button) — see
            // slice 09a spec, § Files to Touch #6. The receiver half is
            // dropped immediately; the Sender stays valid with zero
            // subscribers (Implementation Notes #2).
            let (state_push_tx, _): (server::StatePushTx, _) = broadcast::channel(16);
            app.manage(state_push_tx.clone());
            // Receiver dropped immediately, same as state_push_tx above;
            // config_sync_debounce::run holds the only sender.
            let (config_changed_tx, _): (server::ConfigChangedTx, _) = broadcast::channel(16);
            // Receiver dropped immediately, same as state_push_tx and
            // config_changed_tx. The D→M profile_switch announce (10a) —
            // see docs/slices/10a. Auto Profile Switch.spec.md, § Interface.
            let (profile_switch_tx, _): (server::ProfileSwitchTx, _) = broadcast::channel(16);
            app.manage(profile_switch_tx.clone());
            // save_config sends on this after a write; server::run's own
            // clone lets a mobile-requested profile_switch feed it too —
            // see slice 10 spec, § Interface.
            let (dirty_tx, dirty_rx): (ConfigDirtyTx, _) = tokio::sync::mpsc::unbounded_channel();
            app.manage(dirty_tx.clone());
            tauri::async_runtime::spawn(config_sync_debounce::run(
                config_path.clone(),
                dirty_rx,
                config_changed_tx.clone(),
            ));
            focus_watcher::spawn(
                config_path.clone(),
                dirty_tx.clone(),
                profile_switch_tx.clone(),
                handle.clone(),
            );
            tauri::async_runtime::spawn(server::run(
                pairing,
                config_path,
                switch_state_path,
                switch_states,
                state_push_tx,
                config_changed_tx,
                dirty_tx,
                profile_switch_tx,
                handle.clone(),
            ));
            Ok(())
        })
        .invoke_handler(tauri::generate_handler![
            get_config,
            save_config,
            switch_profile,
            run_actions,
            get_pairing_qr,
            get_device_name,
            set_device_name,
            get_switch_states,
            test_button,
            list_running_apps,
            is_auto_switch_supported,
            get_app_association,
            set_app_association
        ])
        .build(tauri::generate_context!())
        .expect("error while building tauri application")
        .run(|app_handle, event| {
            if let tauri::RunEvent::Exit = event {
                // Sends the mDNS goodbye packet before the process actually
                // exits — see `mdns::Advertisement::goodbye`.
                app_handle.state::<Arc<mdns::Advertisement>>().goodbye();
            }
        });
}
