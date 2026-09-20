pub fn is_supported() -> bool {
    false
}

pub fn spawn(
    _config_path: std::path::PathBuf,
    _dirty_tx: crate::ConfigDirtyTx,
    _profile_switch_tx: crate::server::ProfileSwitchTx,
    _app: tauri::AppHandle,
) {
}

pub async fn running_apps(_app: tauri::AppHandle) -> Vec<(String, String)> {
    Vec::new()
}
