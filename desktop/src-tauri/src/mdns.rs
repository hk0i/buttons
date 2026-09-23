use crate::server::PORT;
use mdns_sd::{ServiceDaemon, ServiceInfo};
use std::collections::HashMap;

const SERVICE_TYPE: &str = "_buttons._tcp.local.";
const INSTANCE_NAME: &str = "buttons-desktop";

/// Owns the mDNS advertisement so it can be re-announced under a new name
/// without restarting the server. `device_id` never changes, so it's fixed
/// at construction; only the instance name is ever replaced.
pub struct Advertisement {
    daemon: ServiceDaemon,
    device_id: String,
    current_fullname: std::sync::Mutex<String>,
}

impl Advertisement {
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

    /// Sends the mDNS goodbye packet before the process exits.
    ///
    /// `rename()`'s `unregister` is fire-and-forget because the process
    /// keeps running afterward, giving the daemon's background thread time
    /// to flush the goodbye on its own. On exit there's no "later" —
    /// without blocking here, the process can die before the goodbye ever
    /// reaches the wire, leaving browsers holding the PTR record until its
    /// TTL expires (`mdns-sd`'s default is 75 minutes for non-host
    /// records).
    pub fn goodbye(&self) {
        let fullname = self.current_fullname.lock().unwrap().clone();
        if let Ok(receiver) = self.daemon.unregister(&fullname) {
            let _ = receiver.recv_timeout(std::time::Duration::from_millis(500));
        }
    }

    fn build_service_info(device_id: &str, device_name: &str) -> mdns_sd::Result<ServiceInfo> {
        let host_name = format!("{INSTANCE_NAME}.local.");
        let mut txt = HashMap::new();
        txt.insert("device_id".to_string(), device_id.to_string());
        Ok(ServiceInfo::new(SERVICE_TYPE, device_name, &host_name, "", PORT, Some(txt))?.enable_addr_auto())
    }
}
