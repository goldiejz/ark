use crate::app::App;
use ratatui::{
    layout::{Constraint, Direction, Layout, Rect},
    style::{Color, Modifier, Style},
    text::{Line, Span},
    widgets::{Block, Borders, Gauge, Paragraph},
    Frame,
};

pub fn render(f: &mut Frame, app: &App, area: Rect) {
    let chunks = Layout::default()
        .direction(Direction::Vertical)
        .constraints([Constraint::Length(10), Constraint::Min(0)])
        .split(area);

    // Top: KPI cards
    let kpi_chunks = Layout::default()
        .direction(Direction::Horizontal)
        .constraints([
            Constraint::Percentage(25),
            Constraint::Percentage(25),
            Constraint::Percentage(25),
            Constraint::Percentage(25),
        ])
        .split(chunks[0]);

    render_kpi(
        f,
        kpi_chunks[0],
        "Projects",
        &app.projects.len().to_string(),
        Color::Cyan,
    );
    render_kpi(
        f,
        kpi_chunks[1],
        "Employees",
        &app.employees.len().to_string(),
        Color::Magenta,
    );
    render_kpi(
        f,
        kpi_chunks[2],
        "Lessons",
        &app.total_lessons.to_string(),
        Color::Green,
    );
    render_kpi(
        f,
        kpi_chunks[3],
        "Tokens (month)",
        &format_number(app.total_tokens),
        Color::Yellow,
    );

    // Bottom: aggregate budget bar + status breakdown
    let bottom = Layout::default()
        .direction(Direction::Horizontal)
        .constraints([Constraint::Percentage(50), Constraint::Percentage(50)])
        .split(chunks[1]);

    render_budget_summary(f, app, bottom[0]);
    render_status_summary(f, app, bottom[1]);
}

fn render_kpi(f: &mut Frame, area: Rect, label: &str, value: &str, color: Color) {
    let para = Paragraph::new(vec![
        Line::from(""),
        Line::from(Span::styled(
            value.to_string(),
            Style::default().fg(color).add_modifier(Modifier::BOLD),
        )),
        Line::from(""),
        Line::from(Span::styled(
            label.to_uppercase(),
            Style::default().fg(Color::DarkGray),
        )),
    ])
    .alignment(ratatui::layout::Alignment::Center)
    .block(Block::default().borders(Borders::ALL));
    f.render_widget(para, area);
}

fn render_budget_summary(f: &mut Frame, app: &App, area: Rect) {
    let layout = Layout::default()
        .direction(Direction::Vertical)
        .margin(1)
        .constraints(vec![Constraint::Length(2); 5.min(app.projects.len().max(1))])
        .split(area);

    let block = Block::default()
        .borders(Borders::ALL)
        .title(Span::styled(
            "  Budget Tier per Project  ",
            Style::default().fg(Color::Cyan),
        ));
    f.render_widget(block, area);

    for (idx, project) in app.projects.iter().take(layout.len()).enumerate() {
        let pct = match project.budget_tier.as_str() {
            "GREEN" => 25,
            "YELLOW" => 60,
            "ORANGE" => 78,
            "RED" => 90,
            "BLACK" => 100,
            _ => 0,
        };
        let color = match project.budget_tier.as_str() {
            "GREEN" => Color::Green,
            "YELLOW" => Color::Yellow,
            "ORANGE" => Color::LightRed,
            "RED" => Color::Red,
            "BLACK" => Color::DarkGray,
            _ => Color::Gray,
        };
        let label = format!("{} [{}]", project.name, project.budget_tier);
        let gauge = Gauge::default()
            .gauge_style(Style::default().fg(color))
            .ratio((pct as f64) / 100.0)
            .label(label);
        f.render_widget(gauge, layout[idx]);
    }
}

fn render_status_summary(f: &mut Frame, app: &App, area: Rect) {
    let mut counts = std::collections::BTreeMap::new();
    for p in &app.projects {
        *counts.entry(p.status.clone()).or_insert(0u64) += 1;
    }

    let lines: Vec<Line> = counts
        .iter()
        .map(|(k, v)| {
            let color = match k.as_str() {
                s if s.contains("complete") || s.contains("delivered") => Color::Green,
                s if s.contains("blocked") => Color::Red,
                s if s.contains("progress") => Color::Yellow,
                _ => Color::Gray,
            };
            Line::from(vec![
                Span::styled(
                    format!("  {:>3}  ", v),
                    Style::default().fg(color).add_modifier(Modifier::BOLD),
                ),
                Span::raw(k.clone()),
            ])
        })
        .collect();

    let para = Paragraph::new(lines).block(
        Block::default()
            .borders(Borders::ALL)
            .title("  Status Breakdown  "),
    );
    f.render_widget(para, area);
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
