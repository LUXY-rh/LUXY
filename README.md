<p align="center">
  <img src="assets/brand/luxy-logo.svg" alt="LUXY" width="96">
</p>

<h1 align="center">LUXY</h1>
<p align="center"><strong>Fair launches on Robinhood Chain. Priced by math, not middlemen.</strong></p>

<p align="center">
  <img src="https://img.shields.io/badge/chain-Robinhood%20Chain%20·%204663-1F4B8F" alt="Chain">
  <img src="https://img.shields.io/badge/license-MIT-green" alt="License">
  <img src="https://img.shields.io/badge/status-curve%20live-brightgreen" alt="Status">
  <img src="https://img.shields.io/badge/audit-in%20progress-yellow" alt="Audit">
</p>

---

### What is LUXY?

A bonding-curve launchpad deployed on **Robinhood Chain (chain ID 4663)**. Deploy tokens in one signature, let a deterministic curve price them, and graduate into public liquidity — all on-chain, all transparent.

- **No presale.** No team allocation. No special-access round.
- **On-chain quotes.** The buy/sell screen reads the same function that executes your trade.
- **Automatic graduation.** At the reserve target, remaining supply + ETH are paired into Uniswap V3.
- **Contract-enforced limits.** Max wallet, max buy per tx, fee ceiling — all hard-coded.

---

### Lifecycle

```
DEPLOY  →  DISCOVER  →  GRADUATE  →  EARN
```

| Step | Action | Detail |
|------|--------|--------|
| **01 Deploy** | One signature | Name + ticker + optional metadata. Token + curve deployed atomically. |
| **02 Discover** | Curve pricing | `P(s) = P₀ + ΔP · s²` reads on-chain state. Buys lift the quote. |
| **03 Graduate** | ≈3.96 ETH target | Curve stops quoting. Remaining supply + ETH → Uniswap V3 LP. |
| **04 Earn** | Stake LP | Pro-rata yield from graduated pools. No lock period. Manual claims. |

---

### Contract Parameters

| Parameter | Value | Enforced |
|-----------|-------|----------|
| Minimum buy | 1 token | On transfer |
| Max buy per tx | 5% of curve target | On swap |
| Max wallet | 5% of total supply | On every transfer |
| Fee ceiling | 5% | Hard-coded |
| Migration target | ≈3.96 ETH | Curve contract |
| Destination | Uniswap V3 | Immutable after deploy |

---

### Quick Start

1. Visit **[luxy-rh.com](https://luxy-rh.com)**
2. Connect your wallet (MetaMask or Rabby)
3. Switch to **Robinhood Chain (4663)**
4. Browse deployed tokens or create your own
5. Buy tokens on the bonding curve — price is set by math, not middlemen

> Deploy in one signature. Curve pricing. Automatic graduation.

---

### Project Structure

```
├── index.html              # Landing page + splash screen + launches
├── docs.html               # Full documentation (9 sections)
├── splash-screen.html      # Standalone splash animation
├── vercel.json             # Vercel deployment config
├── assets/
│   ├── brand/
│   │   ├── luxy-logo.png
│   │   ├── luxy-logo.svg
│   │   └── luxy-twitter-banner.svg
│   └── tokens/
│       └── test-logo.svg   # Example token logo
├── contracts/              # Solidity smart contracts (Foundry)
├── api/                    # TypeScript API server + indexer
├── README.md
└── LICENSE
```

---

### Links

- 🌐 [luxy-rh.com](https://luxy-rh.com)
- 📚 [Docs](https://luxy-rh.com/docs)
- 🔍 [Blockscout Explorer](https://blockscout.com/rhc/)
- ⛓️ Robinhood Chain · 4663

---

### Security

LUXY is **non-custodial at execution**, not governance-free. The boundary between code guarantees and administrative scope is documented in full at [luxy-rh.com/docs](https://luxy-rh.com/docs).

- ✅ Trade pricing — settled atomically by the curve contract
- ✅ Slippage protection — signed minimum-received checked on-chain
- ✅ Max wallet — 5% cap enforced on every transfer
- ✅ Pool protection — destination pool locked until curve completes
- ⚠️ Governance — can pause launches, block addresses, set fee params (within hard limits)

---

### License

MIT © 2026 LUXY

---

<p align="center"><sub>Built for launches that become markets.</sub></p>
