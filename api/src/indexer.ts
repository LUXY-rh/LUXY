import "dotenv/config";
import { ethers } from "ethers";
import { db, getLastIndexedBlock, setLastIndexedBlock } from "./db.js";
import factoryAbi from "./abi/LuxyFactory.json" with { type: "json" };
import curveAbi from "./abi/LuxyCurve.json" with { type: "json" };
import referralAbi from "./abi/ReferralRegistry.json" with { type: "json" };

const RPC_URL = process.env.RPC_URL!;
const FACTORY_ADDRESS = process.env.FACTORY_ADDRESS!;
const REFERRAL_REGISTRY_ADDRESS = process.env.REFERRAL_REGISTRY_ADDRESS;
const START_BLOCK = Number(process.env.START_BLOCK || 0);
const CHUNK_SIZE = 2000; // blocks per getLogs call, tune per RPC provider limits

const provider = new ethers.JsonRpcProvider(RPC_URL);
const factory = new ethers.Contract(FACTORY_ADDRESS, factoryAbi, provider);
const curveInterface = new ethers.Interface(curveAbi as any);
const referralInterface = new ethers.Interface(referralAbi as any);

const upsertReferrerCode = db.prepare(`
  INSERT INTO referrers (address, code) VALUES (@address, @code)
  ON CONFLICT(address) DO UPDATE SET code = excluded.code
`);

const updateReferrerCredit = db.prepare(`
  UPDATE referrers SET
    lifetime_volume = CAST(CAST(lifetime_volume AS INTEGER) + @volume AS TEXT),
    accrued = CAST(CAST(accrued AS INTEGER) + @amount AS TEXT)
  WHERE address = @address
`);

const upsertToken = db.prepare(`
  INSERT INTO tokens (token_address, curve_address, pool_address, creator, name, symbol, created_at)
  VALUES (@token_address, @curve_address, @pool_address, @creator, @name, @symbol, @created_at)
  ON CONFLICT(token_address) DO NOTHING
`);

const insertTrade = db.prepare(`
  INSERT INTO trades (token_address, trader, side, eth_amount, token_amount, fee, tx_hash, block_number, block_timestamp)
  VALUES (@token_address, @trader, @side, @eth_amount, @token_amount, @fee, @tx_hash, @block_number, @block_timestamp)
`);

const updateCurveState = db.prepare(`
  UPDATE tokens SET tokens_sold = ?, reserve_balance = ? WHERE token_address = ?
`);

const markGraduated = db.prepare(`
  UPDATE tokens SET graduated = 1, graduated_at = ? WHERE token_address = ?
`);

// Every curve address we've seen a LaunchCreated event for, kept in memory
// for the duration of the process (re-derived from the DB on restart).
const knownCurves = new Map<string, string>(); // curveAddress -> tokenAddress

function loadKnownCurvesFromDb() {
  const rows = db.prepare("SELECT token_address, curve_address FROM tokens").all() as {
    token_address: string;
    curve_address: string;
  }[];
  for (const r of rows) knownCurves.set(r.curve_address.toLowerCase(), r.token_address);
}

async function processRange(fromBlock: number, toBlock: number) {
  // 1. New launches from the factory.
  const launchLogs = await factory.queryFilter(factory.getEvent("LaunchCreated"), fromBlock, toBlock);
  for (const log of launchLogs) {
    const { token, curve, creator, name, symbol, pool } = (log as ethers.EventLog).args;
    const block = await log.getBlock();
    upsertToken.run({
      token_address: token.toLowerCase(),
      curve_address: curve.toLowerCase(),
      pool_address: pool && pool !== ethers.ZeroAddress ? pool.toLowerCase() : null,
      creator: creator.toLowerCase(),
      name,
      symbol,
      created_at: block.timestamp,
    });
    knownCurves.set(curve.toLowerCase(), token.toLowerCase());
    console.log(`[indexer] new launch ${symbol} token=${token} curve=${curve}`);
  }

  // 2. Buy/Sell/Graduated from every known curve. Filtering logs by topic
  //    across all curve addresses in one getLogs call, then dispatching by
  //    contract address, scales far better than one filter per curve.
  if (knownCurves.size === 0) return;

  const curveAddresses = Array.from(knownCurves.keys());
  const topics = [
    [
      curveInterface.getEvent("Buy")!.topicHash,
      curveInterface.getEvent("Sell")!.topicHash,
      curveInterface.getEvent("Graduated")!.topicHash,
    ],
  ];

  const logs = await provider.getLogs({
    address: curveAddresses,
    fromBlock,
    toBlock,
    topics,
  });

  for (const log of logs) {
    const tokenAddress = knownCurves.get(log.address.toLowerCase());
    if (!tokenAddress) continue;

    const parsed = curveInterface.parseLog(log);
    if (!parsed) continue;
    const block = await provider.getBlock(log.blockNumber);
    const ts = block!.timestamp;

    if (parsed.name === "Buy") {
      const { buyer, ethIn, tokensOut, feePaid } = parsed.args;
      insertTrade.run({
        token_address: tokenAddress,
        trader: buyer.toLowerCase(),
        side: "buy",
        eth_amount: ethIn.toString(),
        token_amount: tokensOut.toString(),
        fee: feePaid.toString(),
        tx_hash: log.transactionHash,
        block_number: log.blockNumber,
        block_timestamp: ts,
      });
    } else if (parsed.name === "Sell") {
      const { seller, tokensIn, ethOut, feePaid } = parsed.args;
      insertTrade.run({
        token_address: tokenAddress,
        trader: seller.toLowerCase(),
        side: "sell",
        eth_amount: ethOut.toString(),
        token_amount: tokensIn.toString(),
        fee: feePaid.toString(),
        tx_hash: log.transactionHash,
        block_number: log.blockNumber,
        block_timestamp: ts,
      });
    } else if (parsed.name === "Graduated") {
      markGraduated.run(ts, tokenAddress);
      console.log(`[indexer] token ${tokenAddress} graduated`);
    }

    // Refresh live curve state (tokensSold / reserveBalance) straight from
    // chain rather than accumulating deltas, so it self-heals from any gap.
    const curveContract = new ethers.Contract(log.address, curveAbi, provider);
    const [sold, reserve] = await Promise.all([
      curveContract.tokensSold(),
      curveContract.reserveBalance(),
    ]);
    updateCurveState.run(sold.toString(), reserve.toString(), tokenAddress);
  }
}

async function processReferralRange(fromBlock: number, toBlock: number) {
  if (!REFERRAL_REGISTRY_ADDRESS) return;

  const logs = await provider.getLogs({
    address: REFERRAL_REGISTRY_ADDRESS,
    fromBlock,
    toBlock,
    topics: [[referralInterface.getEvent("CodeRegistered")!.topicHash, referralInterface.getEvent("Credited")!.topicHash]],
  });

  for (const log of logs) {
    const parsed = referralInterface.parseLog(log);
    if (!parsed) continue;
    if (parsed.name === "CodeRegistered") {
      const { referrer, code } = parsed.args;
      upsertReferrerCode.run({ address: referrer.toLowerCase(), code });
    } else if (parsed.name === "Credited") {
      const { referrer, volume, amount } = parsed.args;
      updateReferrerCredit.run({
        address: referrer.toLowerCase(),
        volume: volume.toString(),
        amount: amount.toString(),
      });
    }
  }
}

async function main() {
  loadKnownCurvesFromDb();

  let fromBlock = Math.max(getLastIndexedBlock(), START_BLOCK);
  console.log(`[indexer] starting from block ${fromBlock}`);

  // Historical backfill in chunks, then switch to polling for new blocks.
  const latest = await provider.getBlockNumber();
  while (fromBlock < latest) {
    const toBlock = Math.min(fromBlock + CHUNK_SIZE, latest);
    await processRange(fromBlock, toBlock);
    await processReferralRange(fromBlock, toBlock);
    setLastIndexedBlock(toBlock);
    fromBlock = toBlock + 1;
  }

  console.log("[indexer] backfill complete, polling for new blocks every 5s");
  setInterval(async () => {
    try {
      const currentLast = getLastIndexedBlock();
      const currentLatest = await provider.getBlockNumber();
      if (currentLatest > currentLast) {
        await processRange(currentLast + 1, currentLatest);
        await processReferralRange(currentLast + 1, currentLatest);
        setLastIndexedBlock(currentLatest);
      }
    } catch (err) {
      console.error("[indexer] poll error", err);
    }
  }, 5000);
}

main().catch((err) => {
  console.error("[indexer] fatal error", err);
  process.exit(1);
});
