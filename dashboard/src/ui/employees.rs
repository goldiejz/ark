use crate::{app::App, employees};
use ratatui::{
    layout::{Constraint, Rect},
    style::{Color, Modifier, Style},
    text::Line,
    widgets::{Block, Borders, Cell, Row, Table, TableState},
    Frame,
};

pub fn render(f: &mut Frame, app: &App, area: Rect) {
    let header = Row::new(vec![
        Cell::from("ID"),
        Cell::from("TITLE"),
        Cell::from("DEPT"),
        Cell::from("DISPATCH"),
        Cell::from("COST"),
        Cell::from("STATUS"),
        Cell::from("TASKS"),
        Cell::from("SKILLS"),
    ])
    .style(
        Style::default()
            .fg(Color::Black)
            .bg(Color::Cyan)
            .add_modifier(Modifier::BOLD),
    );

    let rows: Vec<Row> = app
        .employees
        .iter()
        .map(|e| {
            let dispatch_kind = e.dispatch.kind.clone();
            let dispatch_detail = match dispatch_kind.as_str() {
                "claude-subagent" => e
                    .dispatch
                    .subagent_type
                    .clone()
                    .unwrap_or_else(|| "?".into()),
                "cli" => e.dispatch.command.clone().unwrap_or_else(|| "?".into()),
                "api" => e.dispatch.model.clone().unwrap_or_else(|| "?".into()),
                _ => "?".into(),
            };
            Row::new(vec![
                Cell::from(e.id.clone()).style(Style::default().fg(Color::White).add_modifier(Modifier::BOLD)),
                Cell::from(e.title.clone()),
                Cell::from(e.department.clone()).style(Style::default().fg(Color::Magenta)),
                Cell::from(format!("{}: {}", dispatch_kind, dispatch_detail)),
                Cell::from(e.cost_per_task.clone())
                    .style(Style::default().fg(employees::cost_color(&e.cost_per_task))),
                Cell::from(e.status.clone())
                    .style(Style::default().fg(employees::status_color(&e.status))),
                Cell::from(e.tasks_completed.to_string()),
                Cell::from(e.skills.join(", ")).style(Style::default().fg(Color::Gray)),
            ])
        })
        .collect();

    let widths = [
        Constraint::Length(18),
        Constraint::Length(22),
        Constraint::Length(12),
        Constraint::Length(28),
        Constraint::Length(8),
        Constraint::Length(12),
        Constraint::Length(8),
        Constraint::Min(20),
    ];

    let table = Table::new(rows, widths)
        .header(header)
        .block(
            Block::default()
                .borders(Borders::ALL)
                .title(Line::from(format!(
                    "  Employees ({}) — Drop a JSON in vault/employees/ to add a role  ",
                    app.employees.len()
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
    state.select(Some(app.selected.min(app.employees.len().saturating_sub(1))));
    f.render_stateful_widget(table, area, &mut state);
}
