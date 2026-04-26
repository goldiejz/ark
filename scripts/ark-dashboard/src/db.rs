#![allow(dead_code)]

use rusqlite::{Connection, OpenFlags, Result};
use std::path::Path;

pub struct Db {
    conn: Connection,
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

    // 06.5-04 will add: recent_decisions(), counts_by_class(), etc.
}
