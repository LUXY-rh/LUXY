// Minimal deploy script using ethers.js + solc, no Foundry/Hardhat required.
// Usage: RPC_URL=... PRIVATE_KEY=... node scripts/deploy.js
//
// Deploys, in order: LuxyFactory, ReferralRegistry.
// The graduation handler (Uniswap V3) and per-launch RewardVaults are left
// out of this script since they need real WETH/PositionManager addresses for
// your target chain — deploy UniswapV3GraduationHandler separately once you
// have those, then call factory.setCurveDefaults(...) with its address.

const fs = require("fs");
const path = require("path");
const solc = require("solc");
const { ethers } = require("ethers");
require("dotenv").config({ path: path.resolve(__dirname, "../api/.env") });

function findImports(importPath) {
  const tryPaths = [
    path.resolve(__dirname, "../node_modules", importPath),
    path.resolve(__dirname, "../contracts", importPath),
  ];
  for (const p of tryPaths) {
    if (fs.existsSync(p)) return { contents: fs.readFileSync(p, "utf8") };
  }
  return { error: "File not found: " + importPath };
}

function compile(contractFile) {
  const sources = { [contractFile]: { content: fs.readFileSync(path.resolve(__dirname, "..", contractFile), "utf8") } };
  const input = {
    language: "Solidity",
    sources,
    settings: { outputSelection: { "*": { "*": ["abi", "evm.bytecode.object"] } }, optimizer: { enabled: true, runs: 200 } },
  };
  const output = JSON.parse(solc.compile(JSON.stringify(input), { import: findImports }));
  const errors = (output.errors || []).filter((e) => e.severity === "error");
  if (errors.length) throw new Error(errors.map((e) => e.formattedMessage).join("\n"));
  return output.contracts[contractFile];
}

async function main() {
  const provider = new ethers.JsonRpcProvider(process.env.RPC_URL);
  const wallet = new ethers.Wallet(process.env.PRIVATE_KEY, provider);
  console.log("Deploying from", wallet.address);

  // --- LuxyFactory ---
  const factoryArtifact = compile("contracts/LuxyFactory.sol").LuxyFactory;
  const FactoryFactory = new ethers.ContractFactory(factoryArtifact.abi, factoryArtifact.evm.bytecode.object, wallet);

  // Curve defaults: P0 and deltaP are in wei, tuned so a ~3.96 ETH reserve
  // graduates a reasonable supply — adjust for your token's target supply.
  const p0 = ethers.parseUnits("0.0000001", "ether");
  const deltaP = ethers.parseUnits("0.0000000001", "ether");
  const graduationTarget = ethers.parseEther("3.96");
  const curveSupply = 800_000_000n; // whole tokens available to the curve
  const feeBps = 100; // 1%

  const factory = await FactoryFactory.deploy(wallet.address, p0, deltaP, graduationTarget, curveSupply, feeBps);
  await factory.waitForDeployment();
  console.log("LuxyFactory deployed:", await factory.getAddress());

  // Deployment fee shown in the "Deploy Token" modal on the site: 0.001 ETH.
  const deploymentFee = ethers.parseEther("0.001");
  await (await factory.setDeploymentFee(deploymentFee, wallet.address)).wait();
  console.log("Deployment fee set to 0.001 ETH, recipient:", wallet.address);

  // Pre-create (uninitialized) Uniswap V3 pools at launch time — skipped
  // unless WETH_ADDRESS / UNISWAP_V3_FACTORY_ADDRESS are set, since those are
  // chain-specific and this sandbox couldn't confirm Robinhood Chain's.
  if (process.env.WETH_ADDRESS && process.env.UNISWAP_V3_FACTORY_ADDRESS) {
    await (
      await factory.setPoolConfig(process.env.UNISWAP_V3_FACTORY_ADDRESS, process.env.WETH_ADDRESS, 3000)
    ).wait();
    console.log("Pool pre-creation config set (fee tier 0.3%)");
  } else {
    console.log("Skipped pool pre-creation config — set WETH_ADDRESS + UNISWAP_V3_FACTORY_ADDRESS in api/.env and re-run factory.setPoolConfig(...) once known.");
  }

  // --- ReferralRegistry ---
  const referralArtifact = compile("contracts/ReferralRegistry.sol").ReferralRegistry;
  const ReferralFactory = new ethers.ContractFactory(referralArtifact.abi, referralArtifact.evm.bytecode.object, wallet);
  const referral = await ReferralFactory.deploy(wallet.address);
  await referral.waitForDeployment();
  console.log("ReferralRegistry deployed:", await referral.getAddress());

  console.log("\nAdd these to api/.env:");
  console.log("FACTORY_ADDRESS=" + (await factory.getAddress()));
  console.log("REFERRAL_REGISTRY_ADDRESS=" + (await referral.getAddress()));
  console.log("START_BLOCK=" + (await provider.getBlockNumber()));
}

main().catch((err) => {
  console.error(err);
  process.exit(1);
});
