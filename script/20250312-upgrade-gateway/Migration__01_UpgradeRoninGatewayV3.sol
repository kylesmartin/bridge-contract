// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import { Migration } from "script/Migration.s.sol";

import { IBridgeManager } from "@ronin/contracts/interfaces/bridge/IBridgeManager.sol";
import { Proposal } from "src/libraries/Proposal.sol";
import { Ballot } from "src/libraries/Ballot.sol";

import { Vm } from "forge-std/Vm.sol";

import { LibProxy } from "@fdk/libraries/LibProxy.sol";
import { TNetwork } from "@fdk/types/TNetwork.sol";

import { ITransparentUpgradeableProxyV2 } from "script/interfaces/ITransparentUpgradeableProxyV2.sol";
import { IRoninBridgeManager } from "script/interfaces/IRoninBridgeManager.sol";
import { IMainchainBridgeManager } from "script/interfaces/IMainchainBridgeManager.sol";

import { LibCompanionNetwork } from "script/shared/libraries/LibCompanionNetwork.sol";
import { LibProposal } from "script/shared/libraries/LibProposal.sol";
import { Contract } from "script/utils/Contract.sol";

contract Migration__01_UpgradeRoninGatewayV3 is Migration {
  function run() public virtual override {
    address newGwLogic = _deployLogic(Contract.RoninGatewayV3.key());
    _propose_upgradeAndRestrictERC20_RoninGatewayV3(newGwLogic);
  }

  function _propose_upgradeAndRestrictERC20_RoninGatewayV3(
    address newGwLogic
  ) internal {
    address gw = loadContract(Contract.RoninGatewayV3.key());
    IRoninBridgeManager ronBM = IRoninBridgeManager(loadContract(Contract.RoninBridgeManager.key()));

    address[] memory targets = new address[](1);
    bytes[] memory callDatas = new bytes[](1);
    uint256[] memory values = new uint256[](1);
    uint256[] memory gasAmounts = new uint256[](1);

    targets[0] = gw;
    callDatas[0] = abi.encodeCall(ITransparentUpgradeableProxyV2.upgradeTo, (newGwLogic));
    values[0] = 0;
    gasAmounts[0] = 1_000_000;

    uint256 nonce = ronBM.round(block.chainid) + 1;
    _ronProposal = LibProposal.createProposal(address(ronBM), nonce, _expiry, targets, values, callDatas, gasAmounts);
    _ronProposal.executor = cfg.executor;

    vm.broadcast(cfg.proposer);
    ronBM.propose(block.chainid, _expiry, cfg.executor, targets, values, callDatas, gasAmounts);
  }
}
