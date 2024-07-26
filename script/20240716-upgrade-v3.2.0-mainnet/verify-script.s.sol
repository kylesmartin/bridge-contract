// // SPDX-License-Identifier: MIT
// pragma solidity ^0.8.19;

// import "./20240716-p2-upgrade-bridge-ronin-chain.s.sol";
// import "./20240716-p3-upgrade-bridge-main-chain.s.sol";
// import { TNetwork } from "@fdk/types/TNetwork.sol";

// contract Verify_Script_20240716 is Migration__20240716_P2_UpgradeBridgeRoninchain, Migration__20240716_P3_UpgradeBridgeMainchain {
//   function setUp() public override(Migration__20240716_P2_UpgradeBridgeRoninchain, Migration__20240716_P3_UpgradeBridgeMainchain) {
//     Migration__20240716_P2_UpgradeBridgeRoninchain.setUp();
//   }

//   function run() public override(Migration__20240716_P2_UpgradeBridgeRoninchain, Migration__20240716_P3_UpgradeBridgeMainchain) {
//     TNetwork currentNetwork = network();
//     TNetwork companionNetwork = config.getCompanionNetwork(currentNetwork);
//     // Migration__20240716_P2_UpgradeBridgeRoninchain.run();

//     CONFIG.createFork(companionNetwork);
//     CONFIG.switchTo(companionNetwork);
//     Migration__20240716_P3_UpgradeBridgeMainchain.run();

//     CONFIG.switchTo(currentNetwork);
//   }
// }
