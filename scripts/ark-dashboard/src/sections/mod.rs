#![allow(dead_code)]

use crate::app::App;
use ratatui::{layout::Rect, Frame};

pub trait Section {
    fn name(&self) -> &'static str;
    fn render(&self, f: &mut Frame, area: Rect, app: &App);
}

pub mod budget;
pub mod drift;
pub mod escalations;
pub mod learning_watch;
pub mod portfolio_grid;
pub mod recent_decisions;
pub mod tier_health;

pub use budget::BudgetSummary;
pub use drift::DriftDetector;
pub use escalations::EscalationsPanel;
pub use learning_watch::LearningWatch;
pub use portfolio_grid::PortfolioGrid;
pub use recent_decisions::RecentDecisions;
pub use tier_health::TierHealth;
