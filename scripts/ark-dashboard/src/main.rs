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
    widgets::Paragraph,
    Frame, Terminal,
};

mod app;
mod db;
mod sections;

use app::App;
use sections::{BudgetSummary, EscalationsPanel, PortfolioGrid, Section};

fn vault_db_path() -> PathBuf {
    if let Ok(p) = std::env::var("ARK_POLICY_DB") {
        return PathBuf::from(p);
    }
    let base = std::env::var("ARK_HOME")
        .unwrap_or_else(|_| format!("{}/vaults/ark", std::env::var("HOME").unwrap_or_default()));
    PathBuf::from(base).join("observability/policy.db")
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
    println!("  1..7                  Jump to section");
    println!("  j / Down / Tab        Next section");
    println!("  k / Up / Shift-Tab    Prev section");
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
        // Best-effort terminal restore on panic so we don't leave the user's
        // shell in raw mode / alt screen.
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

    let app = App::new(db, portfolio_root());

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
    // In --tui-no-alt-screen debug mode (CI/non-TTY), skip raw mode entirely
    // so the binary works against a piped stdin like `echo q | ark-dashboard`.
    // In normal interactive mode, enable raw mode + alt screen.
    if !no_alt_screen {
        enable_raw_mode()?;
    }
    let mut stdout = io::stdout();
    if !no_alt_screen {
        execute!(stdout, EnterAlternateScreen, EnableMouseCapture)?;
    }
    let backend = CrosstermBackend::new(stdout);
    let mut terminal = Terminal::new(backend)?;

    // Run loop wrapped so we always restore on error / panic-bubble.
    let result = run_loop(&mut terminal, &mut app, no_alt_screen);

    // Always restore — order matters (leave alt screen, then disable raw).
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
    let tick_rate = Duration::from_millis(2000);

    // In --tui-no-alt-screen mode, render one frame, read stdin (line-buffered),
    // and quit on 'q'. This is the CI/smoke-test path — no raw mode, no event
    // poll.
    if no_alt_screen {
        terminal.draw(|f| draw(f, app))?;
        let mut buf = String::new();
        let _ = io::stdin().read_line(&mut buf);
        if buf.trim_start().starts_with('q') {
            return Ok(());
        }
        return Ok(());
    }

    loop {
        terminal.draw(|f| draw(f, app))?;

        // Poll up to tick_rate. If event arrives, handle it; if timeout,
        // we fall through to refresh.
        let timeout = tick_rate
            .checked_sub(app.last_tick.elapsed())
            .unwrap_or_else(|| Duration::from_millis(0));
        if event::poll(timeout)? {
            match event::read()? {
                Event::Key(k) if k.kind == KeyEventKind::Press => app.handle_key(k.code),
                _ => {}
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
    let header = Paragraph::new(Line::from(format!(
        " ark-dashboard · vault: {} · projects: {} · decisions: {} ",
        app.portfolio_root.display(),
        app.projects.len(),
        app.recent_decisions.len(),
    )))
    .style(
        Style::default()
            .fg(Color::White)
            .bg(Color::Blue)
            .add_modifier(Modifier::BOLD),
    );
    f.render_widget(header, outer[0]);

    // Body — 3 sections stacked vertically (06.5-05 will extend to 7).
    let body = Layout::default()
        .direction(Direction::Vertical)
        .constraints([
            Constraint::Min(8),     // portfolio grid
            Constraint::Length(8),  // escalations
            Constraint::Length(10), // budget
        ])
        .split(outer[1]);

    PortfolioGrid.render(f, body[0], app);
    EscalationsPanel.render(f, body[1], app);
    BudgetSummary.render(f, body[2], app);

    // Footer
    let footer_text = format!(
        " [q] quit  [1-7] section ({}/{})  [j/k] cycle  [Tab/Shift-Tab] cycle ",
        app.current_section + 1,
        app::NUM_SECTIONS,
    );
    let footer = Paragraph::new(Line::from(footer_text))
        .style(Style::default().fg(Color::DarkGray));
    f.render_widget(footer, outer[2]);
}
