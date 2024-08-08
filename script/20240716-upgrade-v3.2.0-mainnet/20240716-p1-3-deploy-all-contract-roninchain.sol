// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import { ISharedArgument } from "../interfaces/ISharedArgument.sol";
import { Migration } from "../Migration.s.sol";
import { Contract } from "../utils/Contract.sol";
import { WBTC } from "src/tokens/erc20/WBTC.sol";

import "./20240716-deploy-wbtc-helper.s.sol";

contract Migration__20240716_P1_3_DeployAllContract_RoninChain is Migration {
  function run() public returns (WBTC instance) {
    address bridgeRewardLogic = _deployLogic(Contract.BridgeReward.key());
    address bridgeSlashLogic = _deployLogic(Contract.BridgeSlash.key());
    address bridgeTrackingLogic = _deployLogic(Contract.BridgeTracking.key());
    address pauseEnforcerLogic = _deployLogic(Contract.RoninPauseEnforcer.key());
    address roninGatewayV3Logic = _deployLogic(Contract.RoninGatewayV3.key());
  }
}
