use crate::server::PORT;
use mdns_sd::{ServiceDaemon, ServiceInfo};
use std::collections::HashMap;

const SERVICE_TYPE: &str = "_buttons._tcp.local.";
const INSTANCE_NAME: &str = "buttons-desktop";

/// Owns the mDNS advertisement so it can be re-announced under a new name
/// without restarting the server. `device_id` never changes, so it's fixed
/// at construction; only the instance name is ever replaced.
pub struct MdnsAdvertisement {
    daemon: ServiceDaemon,
    device_id: String,
    current_fullname: std::sync::Mutex<String>,
}

impl MdnsAdvertisement {
    pub fn start(device_id: String, device_name: &str) -> Self {
        let daemon = ServiceDaemon::new().expect("failed to create mDNS daemon");
        let service_info =
            Self::build_service_info(&device_id, device_name).expect("valid mDNS service info");
        let fullname = service_info.get_fullname().to_string();
        daemon.register(service_info).expect("failed to register mDNS service");
        Self { daemon, device_id, current_fullname: std::sync::Mutex::new(fullname) }
    }

    /// Re-announces under `new_name` — unregisters the old instance, then
    /// registers a fresh one. This is Bonjour's own goodbye-then-announce
    /// mechanism for a live rename (RFC 6762 §10.1), the same one AirPlay
    /// uses for an instant device rename.
    pub fn rename(&self, new_name: &str) -> Result<(), String> {
        let service_info =
            Self::build_service_info(&self.device_id, new_name).map_err(|e| e.to_string())?;
        let new_fullname = service_info.get_fullname().to_string();
        let old_fullname = self.current_fullname.lock().unwrap().clone();
        self.daemon.unregister(&old_fullname).map_err(|e| e.to_string())?;
        self.daemon.register(service_info).map_err(|e| e.to_string())?;
        *self.current_fullname.lock().unwrap() = new_fullname;
        Ok(())
    }

    fn build_service_info(device_id: &str, device_name: &str) -> mdns_sd::Result<ServiceInfo> {
        let host_name = format!("{INSTANCE_NAME}.local.");
        let mut txt = HashMap::new();
        txt.insert("device_id".to_string(), device_id.to_string());
        Ok(ServiceInfo::new(SERVICE_TYPE, device_name, &host_name, "", PORT, Some(txt))?.enable_addr_auto())
    }
}
