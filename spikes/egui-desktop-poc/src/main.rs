mod button_grid;
mod mock_buttons;

fn main() -> eframe::Result<()> {
    let options = eframe::NativeOptions {
        viewport: egui::ViewportBuilder::default().with_inner_size([800.0, 600.0]),
        ..Default::default()
    };

    let mut order: Vec<usize> = (0..mock_buttons::MOCK_BUTTONS.len()).collect();
    let mut dragging: Option<usize> = None;

    eframe::run_simple_native("egui-desktop-poc", options, move |ctx, _frame| {
        egui::CentralPanel::default().show(ctx, |ui| {
            button_grid::show(ui, &mut order, &mut dragging);
        });
    })
}
