const solc = require('solc');
const fs = require('fs');
const path = require('path');

function findImports(importPath) {
  const tryPaths = [
    path.resolve('node_modules', importPath),
    path.resolve('contracts', importPath),
    path.resolve(importPath),
  ];
  for (const p of tryPaths) {
    if (fs.existsSync(p)) return { contents: fs.readFileSync(p, 'utf8') };
  }
  return { error: 'File not found: ' + importPath };
}

const files = [
  'contracts/LuxyToken.sol',
  'contracts/LuxyCurve.sol',
  'contracts/LuxyFactory.sol',
  'contracts/ReferralRegistry.sol',
  'contracts/RewardVault.sol',
  'contracts/UniswapV3GraduationHandler.sol',
];

const sources = {};
for (const f of files) sources[f] = { content: fs.readFileSync(f, 'utf8') };

const input = {
  language: 'Solidity',
  sources,
  settings: {
    outputSelection: { '*': { '*': ['abi'] } },
    optimizer: { enabled: true, runs: 200 },
  },
};

const output = JSON.parse(solc.compile(JSON.stringify(input), { import: findImports }));

let hasError = false;
if (output.errors) {
  for (const err of output.errors) {
    if (err.severity === 'error') hasError = true;
    console.log(err.severity.toUpperCase() + ': ' + err.formattedMessage);
  }
}
if (!hasError) console.log('\n✅ COMPILE OK — no errors');
else { console.log('\n❌ COMPILE FAILED'); process.exit(1); }
