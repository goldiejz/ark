use crate::app::App;
use ratatui::{
    layout::{Constraint, Rect},
    style::{Color, Modifier, Style},
    text::Line,
    widgets::{Block, Borders, Cell, Row, Table, TableState},
    Frame,
};

pub fn render(f: &mut Frame, app: &App, area: Rect) {
    let header = Row::new(vec![
        Cell::from("PROJECT"),
        Cell::from("PHASE"),
        Cell::from("STATUS"),
        Cell::from("LIFECYCLE"),
        Cell::from("DECISIONS"),
        Cell::from("TOKENS"),
        Cell::from("BUDGET"),
    ])
    .style(
        Style::default()
            .fg(Color::Black)
            .bg(Color::Cyan)
            .add_modifier(Modifier::BOLD),
    );

    let rows: Vec<Row> = app
        .projects
        .iter()
        .map(|p| {
            let tier_color = match p.budget_tier.as_str() {
                "GREEN" => Color::Green,
                "YELLOW" => Color::Yellow,
                "ORANGE" => Color::LightRed,
                "RED" => Color::Red,
                "BLACK" => Color::DarkGray,
                _ => Color::Gray,
            };
            let lifecycle_color = match p.lifecycle.as_str() {
                "active" => Color::Green,
                "maintenance" => Color::Yellow,
                "archived" => Color::DarkGray,
                "sunset" => Color::Red,
                _ => Color::Gray,
            };
            Row::new(vec![
                Cell::from(p.name.clone()).style(Style::default().fg(Color::White).add_modifier(Modifier::BOLD)),
                Cell::from(p.phase.clone()),
                Cell::from(p.status.clone()),
                Cell::from(p.lifecycle.clone()).style(Style::default().fg(lifecycle_color)),
                Cell::from(p.decisions.to_string()),
                Cell::from(format_number(p.tokens_month)),
                Cell::from(p.budget_tier.clone()).style(Style::default().fg(tier_color).add_modifier(Modifier::BOLD)),
            ])
        })
        .collect();

    let widths = [
        Constraint::Length(28),
        Constraint::Length(12),
        Constraint::Length(14),
        Constraint::Length(12),
        Constraint::Length(10),
        Constraint::Length(12),
        Constraint::Length(8),
    ];

    let table = Table::new(rows, widths)
        .header(header)
        .block(
            Block::default()
                .borders(Borders::ALL)
                .title(Line::from(format!(
                    "  Projects ({})  ",
                    app.projects.len()
                )))
                .title_style(Style::default().fg(Color::Cyan)),
        )
        .row_highlight_style(
            Style::default()
                .bg(Color::DarkGray)
                .fg(Color::White)
                .add_modifier(Modifier::BOLD),
        )
        .highlight_symbol("▶ ");

    let mut state = TableState::default();
    state.select(Some(app.selected.min(app.projects.len().saturating_sub(1))));
    f.render_stateful_widget(table, area, &mut state);
}

fn format_number(n: u64) -> String {
    let s = n.to_string();
    let chars: Vec<char> = s.chars().rev().collect();
    let chunks: Vec<String> = chars
        .chunks(3)
        .map(|c| c.iter().collect::<String>())
        .collect();
    chunks.join(",").chars().rev().collect()
}
