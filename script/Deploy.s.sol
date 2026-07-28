// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Script.sol";
import "../contracts/LuxyFactory.sol";

/// @title Deploy LuxyFactory to Robinhood Chain
contract DeployLuxy is Script {
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address feeRecipient = vm.envAddress("FEE_RECIPIENT");

        vm.startBroadcast(deployerPrivateKey);

        LuxyFactory factory = new LuxyFactory(feeRecipient);

        console.log("LuxyFactory deployed at:", address(factory));
        console.log("Fee recipient:", feeRecipient);
        console.log("Governance:", factory.owner());

        vm.stopBroadcast();
    }
}
