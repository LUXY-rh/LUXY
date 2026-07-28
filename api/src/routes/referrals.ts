import { Router } from "express";
import { db } from "../db.js";

export const referralsRouter = Router();

// GET /referrals/:code
referralsRouter.get("/:code", (req, res) => {
  const row = db.prepare("SELECT * FROM referrers WHERE code = ?").get(req.params.code);
  if (!row) return res.status(404).json({ error: "code not found" });
  res.json({ referrer: row });
});

// GET /referrals/leaderboard/top?limit=20
referralsRouter.get("/leaderboard/top", (req, res) => {
  const limit = Math.min(Number(req.query.limit) || 20, 100);
  const rows = db
    .prepare("SELECT * FROM referrers ORDER BY CAST(lifetime_volume AS INTEGER) DESC LIMIT ?")
    .all(limit);
  res.json({ leaderboard: rows });
});
