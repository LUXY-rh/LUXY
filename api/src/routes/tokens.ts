import { Router } from "express";
import { db } from "../db.js";

export const tokensRouter = Router();

// GET /tokens?limit=20&offset=0&graduated=false
tokensRouter.get("/", (req, res) => {
  const limit = Math.min(Number(req.query.limit) || 20, 100);
  const offset = Number(req.query.offset) || 0;
  const graduated = req.query.graduated;

  let query = "SELECT * FROM tokens";
  const params: any[] = [];
  if (graduated === "true" || graduated === "false") {
    query += " WHERE graduated = ?";
    params.push(graduated === "true" ? 1 : 0);
  }
  query += " ORDER BY created_at DESC LIMIT ? OFFSET ?";
  params.push(limit, offset);

  const rows = db.prepare(query).all(...params);
  res.json({ tokens: rows });
});

// GET /tokens/:address
tokensRouter.get("/:address", (req, res) => {
  const address = req.params.address.toLowerCase();
  const token = db.prepare("SELECT * FROM tokens WHERE token_address = ?").get(address);
  if (!token) return res.status(404).json({ error: "token not found" });

  const recentTrades = db
    .prepare("SELECT * FROM trades WHERE token_address = ? ORDER BY block_number DESC LIMIT 50")
    .all(address);

  res.json({ token, recentTrades });
});

// GET /tokens/:address/trades?limit=50&offset=0
tokensRouter.get("/:address/trades", (req, res) => {
  const address = req.params.address.toLowerCase();
  const limit = Math.min(Number(req.query.limit) || 50, 200);
  const offset = Number(req.query.offset) || 0;

  const trades = db
    .prepare("SELECT * FROM trades WHERE token_address = ? ORDER BY block_number DESC LIMIT ? OFFSET ?")
    .all(address, limit, offset);

  res.json({ trades });
});
