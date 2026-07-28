import { Router } from "express";
import { ethers } from "ethers";
import { db } from "../db.js";
import curveAbi from "../abi/LuxyCurve.json" with { type: "json" };

export const curveRouter = Router();

const provider = new ethers.JsonRpcProvider(process.env.RPC_URL);

function curveForToken(tokenAddress: string) {
  const row = db
    .prepare("SELECT curve_address FROM tokens WHERE token_address = ?")
    .get(tokenAddress.toLowerCase()) as { curve_address: string } | undefined;
  if (!row) return null;
  return new ethers.Contract(row.curve_address, curveAbi, provider);
}

// GET /curve/:token/quote-buy?ethIn=0.05
curveRouter.get("/:token/quote-buy", async (req, res) => {
  const curve = curveForToken(req.params.token);
  if (!curve) return res.status(404).json({ error: "token not found" });

  const ethIn = req.query.ethIn as string;
  if (!ethIn) return res.status(400).json({ error: "ethIn query param required" });

  try {
    const [tokensOut, fee] = await curve.quoteBuy(ethers.parseEther(ethIn));
    res.json({ tokensOut: tokensOut.toString(), fee: fee.toString() });
  } catch (err: any) {
    res.status(400).json({ error: err.shortMessage || err.message });
  }
});

// GET /curve/:token/quote-sell?tokenAmount=1000
curveRouter.get("/:token/quote-sell", async (req, res) => {
  const curve = curveForToken(req.params.token);
  if (!curve) return res.status(404).json({ error: "token not found" });

  const tokenAmount = req.query.tokenAmount as string;
  if (!tokenAmount) return res.status(400).json({ error: "tokenAmount query param required" });

  try {
    const [ethOut, fee] = await curve.quoteSell(BigInt(tokenAmount));
    res.json({ ethOut: ethOut.toString(), fee: fee.toString() });
  } catch (err: any) {
    res.status(400).json({ error: err.shortMessage || err.message });
  }
});

// GET /curve/:token/simulate-buy?ethIn=0.05
// Pre-validates a would-be buy against the same checks the contract enforces
// (graduated?, max-buy-per-tx, minimum 1 token out) without sending a tx —
// matches the "simulate before you submit" behavior described on the site.
curveRouter.get("/:token/simulate-buy", async (req, res) => {
  const curve = curveForToken(req.params.token);
  if (!curve) return res.status(404).json({ error: "token not found" });

  const ethInStr = req.query.ethIn as string;
  if (!ethInStr) return res.status(400).json({ error: "ethIn query param required" });
  const ethIn = ethers.parseEther(ethInStr);

  const [graduated, graduationTarget] = await Promise.all([curve.graduated(), curve.graduationTarget()]);
  if (graduated) {
    return res.json({ wouldSucceed: false, reason: "curve already graduated" });
  }

  const maxBuy = (graduationTarget * 500n) / 10000n;
  if (graduationTarget > 0n && ethIn > maxBuy) {
    return res.json({ wouldSucceed: false, reason: "exceeds max buy per tx (5% of graduation target)", maxBuyWei: maxBuy.toString() });
  }

  try {
    const [tokensOut, fee] = await curve.quoteBuy(ethIn);
    if (tokensOut < 1n) {
      return res.json({ wouldSucceed: false, reason: "below minimum buy (1 token)" });
    }
    res.json({ wouldSucceed: true, tokensOut: tokensOut.toString(), fee: fee.toString() });
  } catch (err: any) {
    res.json({ wouldSucceed: false, reason: err.shortMessage || err.message });
  }
});

// GET /curve/:token/state — live tokensSold/reserveBalance straight from chain
curveRouter.get("/:token/state", async (req, res) => {
  const curve = curveForToken(req.params.token);
  if (!curve) return res.status(404).json({ error: "token not found" });

  const [tokensSold, reserveBalance, graduated, graduationTarget] = await Promise.all([
    curve.tokensSold(),
    curve.reserveBalance(),
    curve.graduated(),
    curve.graduationTarget(),
  ]);

  res.json({
    tokensSold: tokensSold.toString(),
    reserveBalance: reserveBalance.toString(),
    graduated,
    graduationTarget: graduationTarget.toString(),
  });
});
