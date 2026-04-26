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
        Cell::from("TIMESTAMP"),
        Cell::from("PROJECT"),
        Cell::from("KIND"),
        Cell::from("DETAIL"),
    ])
    .style(
        Style::default()
            .fg(Color::Black)
            .bg(Color::Cyan)
            .add_modifier(Modifier::BOLD),
    );

    let rows: Vec<Row> = app
        .events
        .iter()
        .map(|e| {
            let kind_color = if e.kind.contains("BUDGET") {
                if e.kind.contains("RED") || e.kind.contains("BLACK") {
                    Color::Red
                } else if e.kind.contains("ORANGE") {
                    Color::LightRed
                } else if e.kind.contains("YELLOW") {
                    Color::Yellow
                } else {
                    Color::Green
                }
            } else if e.kind.contains("DECISION") {
                Color::Cyan
            } else {
                Color::Gray
            };
            Row::new(vec![
                Cell::from(e.timestamp.clone()).style(Style::default().fg(Color::DarkGray)),
                Cell::from(e.project.clone()),
                Cell::from(e.kind.clone())
                    .style(Style::default().fg(kind_color).add_modifier(Modifier::BOLD)),
                Cell::from(e.detail.clone()).style(Style::default().fg(Color::Gray)),
            ])
        })
        .collect();

    let widths = [
        Constraint::Length(22),
        Constraint::Length(28),
        Constraint::Length(20),
        Constraint::Min(40),
    ];

    let table = Table::new(rows, widths)
        .header(header)
        .block(
            Block::default()
                .borders(Borders::ALL)
                .title(Line::from(format!("  Events ({}) — newest first  ", app.events.len())))
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
    state.select(Some(app.selected.min(app.events.len().saturating_sub(1))));
    f.render_stateful_widget(table, area, &mut state);
}
