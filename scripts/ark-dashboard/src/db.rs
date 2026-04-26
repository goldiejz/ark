#![allow(dead_code)]

use rusqlite::{Connection, OpenFlags, Result};
use std::collections::HashMap;
use std::path::{Path, PathBuf};
use std::time::UNIX_EPOCH;

pub struct Db {
    conn: Connection,
}

#[derive(Debug, Clone)]
pub struct Decision {
    pub ts: String,
    pub class: String,
    pub decision: String,
    pub reason: String,
}

#[derive(Debug, Clone)]
pub struct Project {
    pub name: String,
    pub path: PathBuf,
    pub current_phase: String,
    pub last_activity_secs: u64,
    pub customer: String,
    pub budget_used_zar: i64,
    pub budget_cap_zar: i64,
}

impl Db {
    pub fn open_readonly(path: &Path) -> Result<Self> {
        let conn = Connection::open_with_flags(
            path,
            OpenFlags::SQLITE_OPEN_READ_ONLY | OpenFlags::SQLITE_OPEN_NO_MUTEX,
        )?;
        Ok(Self { conn })
    }

    pub fn ping(&self) -> Result<i32> {
        self.conn.query_row("SELECT 1", [], |r| r.get(0))
    }

    pub fn recent_decisions(&self, limit: usize) -> Result<Vec<Decision>> {
        let mut stmt = self.conn.prepare(
            "SELECT ts, class, decision, substr(reason,1,80) FROM decisions \
             ORDER BY ts DESC LIMIT ?1",
        )?;
        let rows = stmt.query_map([limit as i64], |r| {
            Ok(Decision {
                ts: r.get(0)?,
                class: r.get(1)?,
                decision: r.get(2)?,
                reason: r.get(3).unwrap_or_default(),
            })
        })?;
        rows.collect()
    }

    pub fn counts_by_class(&self) -> Result<Vec<(String, i64)>> {
        let mut stmt = self
            .conn
            .prepare("SELECT class, COUNT(*) FROM decisions GROUP BY class")?;
        let rows = stmt.query_map([], |r| Ok((r.get(0)?, r.get(1)?)))?;
        rows.collect()
    }

    pub fn class_counts_since(&self, seconds_ago: u64) -> Result<HashMap<String, usize>> {
        let mut stmt = self.conn.prepare(
            "SELECT class, COUNT(*) FROM decisions \
             WHERE ts > datetime('now', ?1) GROUP BY class",
        )?;
        let modifier = format!("-{} seconds", seconds_ago);
        let rows = stmt.query_map([modifier], |r| {
            let cls: String = r.get(0)?;
            let n: i64 = r.get(1)?;
            Ok((cls, n as usize))
        })?;
        let mut out = HashMap::new();
        for r in rows {
            let (k, v) = r?;
            out.insert(k, v);
        }
        Ok(out)
    }
}

/// Walk `portfolio_root` depth-3 looking for `.planning/STATE.md`.
/// Stdlib only — no walkdir dep. Tolerant on errors (skip + continue).
pub fn discover_projects(portfolio_root: &Path) -> Vec<Project> {
    let mut out = Vec::new();
    if !portfolio_root.is_dir() {
        return out;
    }

    let entries = match std::fs::read_dir(portfolio_root) {
        Ok(e) => e,
        Err(_) => return out,
    };

    for entry in entries.flatten() {
        let proj_path = entry.path();
        if !proj_path.is_dir() {
            continue;
        }
        let state_md = proj_path.join(".planning").join("STATE.md");
        if !state_md.is_file() {
            continue;
        }
        let name = proj_path
            .file_name()
            .map(|s| s.to_string_lossy().to_string())
            .unwrap_or_default();
        if name.is_empty() {
            continue;
        }

        let last_activity_secs = std::fs::metadata(&state_md)
            .ok()
            .and_then(|m| m.modified().ok())
            .and_then(|t| t.duration_since(UNIX_EPOCH).ok())
            .map(|d| d.as_secs())
            .unwrap_or(0);

        let current_phase = parse_current_phase(&state_md).unwrap_or_else(|| "(unknown)".into());
        let customer =
            parse_customer(&proj_path.join(".planning").join("policy.yml")).unwrap_or_else(|| "scratch".into());
        let (used, cap) = parse_budget(&proj_path.join(".planning").join("budget.json"));

        out.push(Project {
            name,
            path: proj_path,
            current_phase,
            last_activity_secs,
            customer,
            budget_used_zar: used,
            budget_cap_zar: cap,
        });
    }
    out
}

fn parse_current_phase(state_md: &Path) -> Option<String> {
    let txt = std::fs::read_to_string(state_md).ok()?;
    let mut in_fm = false;
    let mut fm_dashes = 0;
    for line in txt.lines() {
        if line.trim() == "---" {
            fm_dashes += 1;
            in_fm = fm_dashes == 1;
            if fm_dashes >= 2 {
                break;
            }
            continue;
        }
        if in_fm {
            if let Some(rest) = line.strip_prefix("current_phase:") {
                let v = rest.trim().trim_matches('"').trim_matches('\'').to_string();
                if !v.is_empty() {
                    return Some(v);
                }
            }
        }
    }
    None
}

fn parse_customer(policy_yml: &Path) -> Option<String> {
    let txt = std::fs::read_to_string(policy_yml).ok()?;
    for line in txt.lines() {
        let trimmed = line.trim_start();
        if let Some(rest) = trimmed.strip_prefix("customer:") {
            let v = rest.trim().trim_matches('"').trim_matches('\'').to_string();
            if !v.is_empty() {
                return Some(v);
            }
        }
    }
    None
}

/// Hand-rolled minimal JSON value extractor for keys monthly_used_zar /
/// monthly_cap_zar (also accepts monthly_used / monthly_cap_tokens for
/// Phase-2 schema compat). Returns (used, cap), or (0, 0) on any miss.
fn parse_budget(budget_json: &Path) -> (i64, i64) {
    let txt = match std::fs::read_to_string(budget_json) {
        Ok(s) => s,
        Err(_) => return (0, 0),
    };
    let used = extract_int_field(&txt, "monthly_used_zar")
        .or_else(|| extract_int_field(&txt, "monthly_used"))
        .unwrap_or(0);
    let cap = extract_int_field(&txt, "monthly_cap_zar")
        .or_else(|| extract_int_field(&txt, "monthly_cap_tokens"))
        .unwrap_or(0);
    (used, cap)
}

fn extract_int_field(json: &str, key: &str) -> Option<i64> {
    let needle = format!("\"{}\"", key);
    let idx = json.find(&needle)?;
    let after = &json[idx + needle.len()..];
    let colon = after.find(':')?;
    let rest = &after[colon + 1..];
    // Skip whitespace, then read digits (with optional minus)
    let rest = rest.trim_start();
    let mut end = 0;
    let bytes = rest.as_bytes();
    if bytes.is_empty() {
        return None;
    }
    if bytes[0] == b'-' {
        end += 1;
    }
    while end < bytes.len() && bytes[end].is_ascii_digit() {
        end += 1;
    }
    if end == 0 || (end == 1 && bytes[0] == b'-') {
        return None;
    }
    rest[..end].parse::<i64>().ok()
}

#[cfg(test)]
mod tests {
    use super::*;
    use rusqlite::Connection;

    #[test]
    fn recent_decisions_returns_rows() {
        let tmp = std::env::temp_dir().join(format!("ark-dash-test-{}.db", std::process::id()));
        let _ = std::fs::remove_file(&tmp);
        // Create + seed a fixture DB with a writable connection (test isolation).
        {
            let c = Connection::open(&tmp).unwrap();
            c.execute_batch(
                "CREATE TABLE decisions (ts TEXT, class TEXT, decision TEXT, reason TEXT);
                 INSERT INTO decisions VALUES ('2026-04-26T10:00:00','dispatch','d1','r1');
                 INSERT INTO decisions VALUES ('2026-04-26T11:00:00','escalation','d2','r2');
                 INSERT INTO decisions VALUES ('2026-04-26T12:00:00','budget','d3','r3');",
            )
            .unwrap();
        }
        let db = Db::open_readonly(&tmp).unwrap();
        let rows = db.recent_decisions(5).unwrap();
        assert_eq!(rows.len(), 3);
        assert_eq!(rows[0].class, "budget"); // latest first
        let counts = db.counts_by_class().unwrap();
        assert_eq!(counts.len(), 3);
        let _ = std::fs::remove_file(&tmp);
    }

    #[test]
    fn discover_projects_finds_state_md() {
        let tmp = std::env::temp_dir().join(format!("ark-dash-disc-{}", std::process::id()));
        let _ = std::fs::remove_dir_all(&tmp);
        let proj = tmp.join("proj-a").join(".planning");
        std::fs::create_dir_all(&proj).unwrap();
        std::fs::write(
            proj.join("STATE.md"),
            "---\ncurrent_phase: \"06.5-ceo-dashboard\"\n---\n\n# State\n",
        )
        .unwrap();
        std::fs::write(
            proj.join("policy.yml"),
            "bootstrap:\n  customer: acme-corp\n",
        )
        .unwrap();
        std::fs::write(
            proj.join("budget.json"),
            "{\"monthly_used_zar\": 1234, \"monthly_cap_zar\": 5000}",
        )
        .unwrap();

        let projects = discover_projects(&tmp);
        assert_eq!(projects.len(), 1);
        let p = &projects[0];
        assert_eq!(p.name, "proj-a");
        assert_eq!(p.current_phase, "06.5-ceo-dashboard");
        assert_eq!(p.customer, "acme-corp");
        assert_eq!(p.budget_used_zar, 1234);
        assert_eq!(p.budget_cap_zar, 5000);
        assert!(p.last_activity_secs > 0);

        let _ = std::fs::remove_dir_all(&tmp);
    }

    #[test]
    fn extract_int_field_handles_typical_json() {
        let s = r#"{"monthly_used_zar": 42, "monthly_cap_zar":100}"#;
        assert_eq!(extract_int_field(s, "monthly_used_zar"), Some(42));
        assert_eq!(extract_int_field(s, "monthly_cap_zar"), Some(100));
        assert_eq!(extract_int_field(s, "missing"), None);
    }
}
