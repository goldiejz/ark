use std::path::PathBuf;
use std::process::ExitCode;

mod app;
mod db;
mod sections;

fn vault_db_path() -> PathBuf {
    if let Ok(p) = std::env::var("ARK_POLICY_DB") {
        return PathBuf::from(p);
    }
    let base = std::env::var("ARK_HOME")
        .unwrap_or_else(|_| format!("{}/vaults/ark", std::env::var("HOME").unwrap_or_default()));
    PathBuf::from(base).join("observability/policy.db")
}

fn main() -> ExitCode {
    let args: Vec<String> = std::env::args().collect();
    if args.iter().any(|a| a == "--help" || a == "-h") {
        println!("ark-dashboard — Tier B TUI (Phase 6.5)");
        println!("Usage: ark dashboard --tui");
        println!("Keybindings: j/k navigate · q quit · r mark resolved · Enter drill down");
        return ExitCode::SUCCESS;
    }

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

    // 06.5-04 will replace this with the real terminal setup + run loop.
    // For this plan, we just confirm the connection works and exit.
    println!("ark-dashboard scaffold OK · policy.db reachable");
    let _app = app::App::new(db);
    ExitCode::SUCCESS
}
