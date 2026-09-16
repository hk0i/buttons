mod actions;
mod config;
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

#[tauri::command]
fn save_config(app: tauri::AppHandle, config: Config) -> Result<(), String> {
    config::save_config(&config_path(&app)?, &config)
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
            let switch_states: SwitchStates = switch_state::load(&switch_state_path);
            app.manage(switch_states.clone());
            // Created once at startup, cloned into server::run and into
            // every command that can trigger a flip (test_button) — see
            // slice 09a spec, § Files to Touch #6. The receiver half is
            // dropped immediately; the Sender stays valid with zero
            // subscribers (Implementation Notes #2).
            let (state_push_tx, _): (server::StatePushTx, _) = broadcast::channel(16);
            app.manage(state_push_tx.clone());
            tauri::async_runtime::spawn(server::run(
                pairing,
                config_path,
                switch_state_path,
                switch_states,
                state_push_tx,
                handle.clone(),
            ));
            Ok(())
        })
        .invoke_handler(tauri::generate_handler![
            get_config,
            save_config,
            run_actions,
            get_pairing_qr,
            get_switch_states,
            test_button
        ])
        .run(tauri::generate_context!())
        .expect("error while running tauri application");
}
