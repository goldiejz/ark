#![allow(dead_code)]

use crate::app::App;
use crate::sections::Section;
use ratatui::{
    layout::{Constraint, Rect},
    style::{Color, Modifier, Style},
    widgets::{Block, Borders, Cell, Row, Table},
    Frame,
};
use std::collections::BTreeMap;

pub struct BudgetSummary;

impl Section for BudgetSummary {
    fn name(&self) -> &'static str {
        "Budget"
    }

    fn render(&self, f: &mut Frame, area: Rect, app: &App) {
        // Group by customer (used, cap)
        let mut totals: BTreeMap<String, (i64, i64)> = BTreeMap::new();
        for p in app.projects.iter() {
            let entry = totals.entry(p.customer.clone()).or_insert((0, 0));
            entry.0 += p.budget_used_zar;
            entry.1 += p.budget_cap_zar;
        }

        let header = Row::new(vec!["Customer", "Used", "Cap", "Headroom", "Risk"])
            .style(Style::default().add_modifier(Modifier::BOLD));

        let rows: Vec<Row> = if totals.is_empty() {
            vec![Row::new(vec![Cell::from("(no projects with budgets)")])]
        } else {
            totals
                .iter()
                .map(|(cust, (used, cap))| {
                    let headroom_pct = if *cap <= 0 {
                        100
                    } else {
                        let h = ((*cap - *used) * 100) / *cap;
                        h.max(0)
                    };
                    let (color, status) = if headroom_pct < 10 {
                        (Color::Red, "CAP")
                    } else if headroom_pct < 30 {
                        (Color::Yellow, "tight")
                    } else {
                        (Color::Green, "ok")
                    };
                    Row::new(vec![
                        Cell::from(cust.clone()),
                        Cell::from(format!("{}", used)),
                        Cell::from(format!("{}", cap)),
                        Cell::from(format!("{}%", headroom_pct)),
                        Cell::from(status).style(Style::default().fg(color)),
                    ])
                })
                .collect()
        };

        let widths = [
            Constraint::Length(24),
            Constraint::Length(12),
            Constraint::Length(12),
            Constraint::Length(10),
            Constraint::Min(8),
        ];

        let table = Table::new(rows, widths).header(header).block(
            Block::default()
                .title(" Budget (per customer, monthly) ")
                .borders(Borders::ALL),
        );

        f.render_widget(table, area);
    }
}
