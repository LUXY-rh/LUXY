import "dotenv/config";
import express from "express";
import cors from "cors";
import { tokensRouter } from "./routes/tokens.js";
import { curveRouter } from "./routes/curve.js";
import { referralsRouter } from "./routes/referrals.js";

const app = express();
app.use(cors());
app.use(express.json());

app.get("/health", (_req, res) => res.json({ ok: true }));

app.use("/tokens", tokensRouter);
app.use("/curve", curveRouter);
app.use("/referrals", referralsRouter);

const port = Number(process.env.PORT) || 8787;
app.listen(port, () => {
  console.log(`[api] listening on http://localhost:${port}`);
});
