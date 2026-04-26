#![allow(dead_code)]

use crate::app::App;
use ratatui::{layout::Rect, Frame};

pub trait Section {
    fn name(&self) -> &'static str;
    fn render(&self, f: &mut Frame, area: Rect, app: &App);
}

pub mod budget;
pub mod escalations;
pub mod portfolio_grid;

pub use budget::BudgetSummary;
pub use escalations::EscalationsPanel;
pub use portfolio_grid::PortfolioGrid;

// 06.5-05 will add: pub mod recent_decisions; pub mod learning_watch; pub mod drift; pub mod tier_health;
