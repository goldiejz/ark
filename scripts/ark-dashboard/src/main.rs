use std::io::{self, Stdout};
use std::path::PathBuf;
use std::process::ExitCode;
use std::time::Duration;

use crossterm::{
    event::{self, DisableMouseCapture, EnableMouseCapture, Event, KeyEventKind},
    execute,
    terminal::{disable_raw_mode, enable_raw_mode, EnterAlternateScreen, LeaveAlternateScreen},
};
use ratatui::{
    backend::CrosstermBackend,
    layout::{Constraint, Direction, Layout},
    style::{Color, Modifier, Style},
    text::Line,
    widgets::{Block, Borders, Clear, Paragraph, Wrap},
    Frame, Terminal,
};

mod app;
mod db;
mod sections;

use app::App;
use sections::{
    BudgetSummary, DriftDetector, EscalationsPanel, LearningWatch, PortfolioGrid, RecentDecisions,
    Section, TierHealth,
};

fn vault_path() -> PathBuf {
    if let Ok(p) = std::env::var("ARK_HOME") {
        return PathBuf::from(p);
    }
    let home = std::env::var("HOME").unwrap_or_default();
    PathBuf::from(home).join("vaults/ark")
}

fn vault_db_path() -> PathBuf {
    if let Ok(p) = std::env::var("ARK_POLICY_DB") {
        return PathBuf::from(p);
    }
    vault_path().join("observability/policy.db")
}

fn portfolio_root() -> PathBuf {
    if let Ok(p) = std::env::var("ARK_PORTFOLIO_ROOT") {
        return PathBuf::from(p);
    }
    let home = std::env::var("HOME").unwrap_or_default();
    PathBuf::from(home).join("code")
}

fn print_help() {
    println!("ark-dashboard — Tier B TUI (Phase 6.5)");
    println!();
    println!("Usage: ark-dashboard [OPTIONS]");
    println!();
    println!("Options:");
    println!("  --help, -h            Show this help and exit");
    println!("  --tui-no-alt-screen   Run TUI without alternate screen (debug/CI)");
    println!();
    println!("Keybindings:");
    println!("  q / Esc               Quit");
    println!("  ?                     Toggle keybinding help overlay");
    println!("  1..7                  Jump to section");
    println!("  j / Down              Scroll within section (or next section)");
    println!("  k / Up                Scroll back (or prev section)");
    println!("  Tab                   Next section");
    println!("  Shift-Tab             Prev section");
    println!("  r                     Refresh now (or resolve selected escalation)");
    println!("  Enter                 Drill-down (reserved)");
    println!();
    println!("Environment:");
    println!("  ARK_POLICY_DB         Override policy.db path");
    println!("  ARK_HOME              Override vault root (default: ~/vaults/ark)");
    println!("  ARK_PORTFOLIO_ROOT    Override portfolio root (default: ~/code)");
    println!("  ARK_ESCALATIONS_FILE  Override ESCALATIONS.md path");
}

fn install_panic_hook() {
    let original = std::panic::take_hook();
    std::panic::set_hook(Box::new(move |info| {
        let _ = disable_raw_mode();
        let _ = execute!(io::stdout(), LeaveAlternateScreen, DisableMouseCapture);
        original(info);
    }));
}

fn main() -> ExitCode {
    let args: Vec<String> = std::env::args().collect();
    if args.iter().any(|a| a == "--help" || a == "-h") {
        print_help();
        return ExitCode::SUCCESS;
    }
    let no_alt_screen = args.iter().any(|a| a == "--tui-no-alt-screen");

    let db = match db::Db::open_readonly(&vault_db_path()) {
        Ok(d) => d,
        Err(e) => {
            eprintln!("Failed to open policy.db read-only: {e}");
            return ExitCode::from(1);
        }
    };
    if let Err(e) = db.ping() {
        eprintln!("policy.db ping failed: {e}");
        return ExitCode::from(1);
    }

    let app = App::new(db, portfolio_root(), vault_path());

    install_panic_hook();

    match run_tui(app, no_alt_screen) {
        Ok(()) => ExitCode::SUCCESS,
        Err(e) => {
            eprintln!("ark-dashboard error: {e}");
            ExitCode::from(1)
        }
    }
}

fn run_tui(mut app: App, no_alt_screen: bool) -> io::Result<()> {
    if !no_alt_screen {
        enable_raw_mode()?;
    }
    let mut stdout = io::stdout();
    if !no_alt_screen {
        execute!(stdout, EnterAlternateScreen, EnableMouseCapture)?;
    }
    let backend = CrosstermBackend::new(stdout);
    let mut terminal = Terminal::new(backend)?;

    let result = run_loop(&mut terminal, &mut app, no_alt_screen);

    if !no_alt_screen {
        disable_raw_mode().ok();
        let _ = execute!(io::stdout(), LeaveAlternateScreen, DisableMouseCapture);
    }
    terminal.show_cursor().ok();

    result
}

fn run_loop(
    terminal: &mut Terminal<CrosstermBackend<Stdout>>,
    app: &mut App,
    no_alt_screen: bool,
) -> io::Result<()> {
    // CI/smoke path: render one frame, read one stdin line, quit on 'q'.
    if no_alt_screen {
        terminal.draw(|f| draw(f, app))?;
        let mut buf = String::new();
        let _ = io::stdin().read_line(&mut buf);
        return Ok(());
    }

    let tick_rate = Duration::from_secs(2);
    loop {
        terminal.draw(|f| draw(f, app))?;

        // Poll up to 500ms — keypresses stay sub-second, the 2s tick is
        // gated by `last_tick.elapsed()` not the poll timeout.
        if event::poll(Duration::from_millis(500))? {
            if let Event::Key(k) = event::read()? {
                if k.kind == KeyEventKind::Press {
                    app.handle_key(k.code);
                }
            }
        }

        if app.last_tick.elapsed() >= tick_rate {
            app.refresh();
        }

        if app.should_quit {
            return Ok(());
        }
    }
}

fn now_hms() -> String {
    use std::time::{SystemTime, UNIX_EPOCH};
    let secs = SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map(|d| d.as_secs())
        .unwrap_or(0);
    let h = (secs / 3600) % 24;
    let m = (secs / 60) % 60;
    let s = secs % 60;
    format!("{:02}:{:02}:{:02}", h, m, s)
}

const SECTION_TITLES: [&str; 7] = [
    "Portfolio",
    "Escalations",
    "Budget",
    "Recent Decisions",
    "Learning Watch",
    "Drift",
    "Tier Health",
];

fn draw(f: &mut Frame, app: &App) {
    let outer = Layout::default()
        .direction(Direction::Vertical)
        .constraints([
            Constraint::Length(1), // header
            Constraint::Min(0),    // body
            Constraint::Length(1), // footer
        ])
        .split(f.area());

    // Header
    let active_title = SECTION_TITLES
        .get(app.current_section)
        .copied()
        .unwrap_or("");
    let header_text = format!(
        " ark-dashboard · vault: {} · active: [{}] {} · last refresh: {} ",
        app.portfolio_root.display(),
        app.current_section + 1,
        active_title,
        now_hms(),
    );
    let header = Paragraph::new(Line::from(header_text)).style(
        Style::default()
            .fg(Color::White)
            .bg(Color::Blue)
            .add_modifier(Modifier::BOLD),
    );
    f.render_widget(header, outer[0]);

    // Body — 7 sections stacked vertically (tall-terminal layout).
    let body = Layout::default()
        .direction(Direction::Vertical)
        .constraints([
            Constraint::Length(8),  // 1. portfolio
            Constraint::Length(6),  // 2. escalations
            Constraint::Length(7),  // 3. budget
            Constraint::Min(8),     // 4. recent decisions (flex)
            Constraint::Length(8),  // 5. learning watch
            Constraint::Length(7),  // 6. drift
            Constraint::Length(8),  // 7. tier health
        ])
        .split(outer[1]);

    PortfolioGrid.render(f, body[0], app);
    EscalationsPanel.render(f, body[1], app);
    BudgetSummary.render(f, body[2], app);
    RecentDecisions.render(f, body[3], app);
    LearningWatch.render(f, body[4], app);
    DriftDetector.render(f, body[5], app);
    TierHealth.render(f, body[6], app);

    // Footer
    let footer_text = format!(
        " [q] quit  [1-7] section ({}/{})  [j/k] scroll  [Tab/S-Tab] cycle  [r] refresh  [?] help ",
        app.current_section + 1,
        app::NUM_SECTIONS,
    );
    let footer = Paragraph::new(Line::from(footer_text))
        .style(Style::default().fg(Color::DarkGray));
    f.render_widget(footer, outer[2]);

    if app.show_help {
        draw_help_overlay(f);
    }
}

fn draw_help_overlay(f: &mut Frame) {
    let area = f.area();
    let w = area.width.min(60);
    let h = 14u16.min(area.height);
    let x = area.x + (area.width.saturating_sub(w)) / 2;
    let y = area.y + (area.height.saturating_sub(h)) / 2;
    let rect = ratatui::layout::Rect { x, y, width: w, height: h };

    f.render_widget(Clear, rect);
    let help_lines = vec![
        Line::from("ark-dashboard keybindings"),
        Line::from(""),
        Line::from(" q / Esc        Quit"),
        Line::from(" ?              Toggle this overlay"),
        Line::from(" 1..7           Jump to section"),
        Line::from(" j / Down       Scroll / next section"),
        Line::from(" k / Up         Scroll back / prev section"),
        Line::from(" Tab / S-Tab    Cycle sections"),
        Line::from(" r              Refresh / resolve escalation"),
        Line::from(" Enter          Drill-down (reserved)"),
    ];
    let p = Paragraph::new(help_lines)
        .block(
            Block::default()
                .title(" Help ")
                .borders(Borders::ALL)
                .border_style(Style::default().fg(Color::Yellow)),
        )
        .wrap(Wrap { trim: false });
    f.render_widget(p, rect);
}
