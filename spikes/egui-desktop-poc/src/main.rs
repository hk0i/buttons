fn main() -> eframe::Result<()> {
    let options = eframe::NativeOptions {
        viewport: egui::ViewportBuilder::default().with_inner_size([800.0, 600.0]),
        ..Default::default()
    };
    eframe::run_simple_native("egui-desktop-poc", options, |ctx, _frame| {
        egui::CentralPanel::default().show(ctx, |ui| {
            ui.heading("egui desktop POC — boot check");
        });
    })
}
