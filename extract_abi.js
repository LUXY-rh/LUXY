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

const wanted = ['LuxyToken', 'LuxyCurve', 'LuxyFactory', 'ReferralRegistry', 'RewardVault'];
fs.mkdirSync('api/src/abi', { recursive: true });
for (const file of Object.keys(output.contracts)) {
  for (const name of Object.keys(output.contracts[file])) {
    if (wanted.includes(name)) {
      fs.writeFileSync(`api/src/abi/${name}.json`, JSON.stringify(output.contracts[file][name].abi, null, 2));
      console.log('wrote', name);
    }
  }
}
