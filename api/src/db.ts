import Database from "better-sqlite3";
import fs from "node:fs";
import path from "node:path";
import "dotenv/config";

const dbPath = process.env.DB_PATH || "./data/luxy.db";
fs.mkdirSync(path.dirname(dbPath), { recursive: true });

export const db = new Database(dbPath);
db.pragma("journal_mode = WAL");

db.exec(`
CREATE TABLE IF NOT EXISTS tokens (
  token_address TEXT PRIMARY KEY,
  curve_address TEXT NOT NULL,
  pool_address TEXT,
  creator TEXT NOT NULL,
  name TEXT NOT NULL,
  symbol TEXT NOT NULL,
  created_at INTEGER NOT NULL,
  tokens_sold TEXT NOT NULL DEFAULT '0',
  reserve_balance TEXT NOT NULL DEFAULT '0',
  graduated INTEGER NOT NULL DEFAULT 0,
  graduated_at INTEGER
);

CREATE TABLE IF NOT EXISTS trades (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  token_address TEXT NOT NULL,
  trader TEXT NOT NULL,
  side TEXT NOT NULL CHECK (side IN ('buy','sell')),
  eth_amount TEXT NOT NULL,
  token_amount TEXT NOT NULL,
  fee TEXT NOT NULL,
  tx_hash TEXT NOT NULL,
  block_number INTEGER NOT NULL,
  block_timestamp INTEGER NOT NULL
);
CREATE INDEX IF NOT EXISTS idx_trades_token ON trades(token_address);
CREATE INDEX IF NOT EXISTS idx_trades_trader ON trades(trader);

CREATE TABLE IF NOT EXISTS referrers (
  address TEXT PRIMARY KEY,
  code TEXT UNIQUE NOT NULL,
  lifetime_volume TEXT NOT NULL DEFAULT '0',
  accrued TEXT NOT NULL DEFAULT '0'
);

-- tracks the last block the indexer has fully processed, so restarts resume
-- instead of re-scanning from START_BLOCK every time.
CREATE TABLE IF NOT EXISTS indexer_state (
  id INTEGER PRIMARY KEY CHECK (id = 1),
  last_block INTEGER NOT NULL
);
INSERT OR IGNORE INTO indexer_state (id, last_block) VALUES (1, 0);
`);

export function getLastIndexedBlock(): number {
  const row = db.prepare("SELECT last_block FROM indexer_state WHERE id = 1").get() as { last_block: number };
  return row.last_block;
}

export function setLastIndexedBlock(block: number) {
  db.prepare("UPDATE indexer_state SET last_block = ? WHERE id = 1").run(block);
}
