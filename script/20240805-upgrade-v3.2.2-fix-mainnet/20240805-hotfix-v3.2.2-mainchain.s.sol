// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import { console } from "forge-std/console.sol";
import { StdStyle } from "forge-std/StdStyle.sol";
import { IRoninBridgeManager } from "script/interfaces/IRoninBridgeManager.sol";
import { IMainchainGatewayV3 } from "@ronin/contracts/interfaces/IMainchainGatewayV3.sol";
import { IRoninGatewayV3 } from "@ronin/contracts/interfaces/IRoninGatewayV3.sol";
import { MinimumWithdrawal } from "@ronin/contracts/extensions/MinimumWithdrawal.sol";
import { GlobalProposal } from "@ronin/contracts/libraries/GlobalProposal.sol";
import { LibTokenInfo, TokenStandard } from "@ronin/contracts/libraries/LibTokenInfo.sol";
import { Contract } from "../utils/Contract.sol";
import { Network } from "../utils/Network.sol";
import { Contract } from "../utils/Contract.sol";
import { ISharedArgument } from "../interfaces/ISharedArgument.sol";
import "@ronin/contracts/ronin/gateway/BridgeReward.sol";
import { IMainchainBridgeManager } from "script/interfaces/IMainchainBridgeManager.sol";
import "@ronin/contracts/mainchain/MainchainGatewayV3.sol";
import "@ronin/contracts/libraries/Proposal.sol";
import "@ronin/contracts/libraries/Ballot.sol";
import { TransparentUpgradeableProxyV2, TransparentUpgradeableProxy } from "@ronin/contracts/extensions/TransparentUpgradeableProxyV2.sol";

import { MockSLP } from "@ronin/contracts/mocks/token/MockSLP.sol";
import { SLPDeploy } from "@ronin/script/contracts/token/SLPDeploy.s.sol";
import { MainchainBridgeAdminUtils } from "test/helpers/MainchainBridgeAdminUtils.t.sol";
import "@ronin/script/contracts/RoninBridgeManagerDeploy.s.sol";
import { DefaultContract } from "@fdk/utils/DefaultContract.sol";
import { DefaultNetwork } from "@fdk/utils/DefaultNetwork.sol";
import { Migration } from "../Migration.s.sol";
import { cheatBroadcast } from "@fdk/utils/Helpers.sol";

import { Migration__MapToken_WBTC_Threshold } from "../20240716-upgrade-v3.2.0-mainnet/wbtc-threshold.s.sol";

contract Migration__20240805_Hotfix_V3_2_0__Mainchain is Migration__MapToken_WBTC_Threshold, Migration
{
  using StdStyle for *;

  ISharedArgument.SharedParameter _param;

  address _multisigEth = 0x51F6696Ae42C6C40CA9F5955EcA2aaaB1Cefb26e;

  function setUp() public virtual override {
    super.setUp();

    vm.label(_multisigEth, "ETH Multisig");
  }

  function run() public virtual onlyOn(Network.EthMainnet.key()) {
    IMainchainBridgeManager mainchainBM = IMainchainBridgeManager(0x2Cf3CFb17774Ce0CFa34bB3f3761904e7fc3FaDB);
    vm.prank(_multisigEth);
    TransparentUpgradeableProxyV2 mainchainBMproxy = TransparentUpgradeableProxyV2(payable(address(mainchainBM)));

    address prevBMLogic = mainchainBMproxy.implementation();
    address newBMLogic = _deployLogic(Contract.MainchainBridgeManager.key());

    // 0. Prank relay running proposal
    {
      bytes32 adminSlot_$ = 0xb53127684a568b3173ae13b9f8a6016e243e63b6e8ee1178d6a717850b5d6103;
      bytes32 adminValue = bytes32(uint256(uint160(_multisigEth)));
      vm.store(address(mainchainBMproxy), adminSlot_$, adminValue);

      address mainchainGW = 0x64192819Ac13Ef72bF6b5AE239AC672B43a9AF08;
      adminValue = bytes32(uint256(uint160(address(mainchainBMproxy))));
      vm.store(address(mainchainGW), adminSlot_$, adminValue);

      // Prank that Mainchain gateway is upgraded
      bytes32 implSlot_$ = 0x360894a13ba1a3210667c828492db98dca3e2076cc3735a920a3ca505d382bbc;
      bytes32 implValue = bytes32(uint256(uint160(0xfc274EC92bBb1A1472884558d1B5CaaC6F8220Ee)));
      vm.store(address(mainchainGW), implSlot_$, implValue);
    }

    // 1. Upgrade to and call
    {
      address[] memory mainchainTokens = new address[](1);
      address[] memory roninTokens = new address[](1);
      TokenStandard[] memory standards = new TokenStandard[](1);
      uint256[][4] memory thresholds;

      mainchainTokens[0] = _wbtcMainchainToken;
      roninTokens[0] = _wbtcRoninToken;
      standards[0] = TokenStandard.ERC20;
      // highTierThreshold
      thresholds[0] = new uint256[](1);
      thresholds[0][0] = _wbtcHighTierThreshold;
      // lockedThreshold
      thresholds[1] = new uint256[](1);
      thresholds[1][0] = _wbtcLockedThreshold;
      // unlockFeePercentages
      thresholds[2] = new uint256[](1);
      thresholds[2][0] = _wbtcUnlockFeePercentages;
      // dailyWithdrawalLimit
      thresholds[3] = new uint256[](1);
      thresholds[3][0] = _wbtcDailyWithdrawalLimit;

      cheatBroadcast({
        from: _multisigEth,
        to: address(mainchainBMproxy),
        callValue: 0,
        callData: abi.encodeWithSignature(
          "upgradeToAndCall(address,bytes)",
          newBMLogic,
          abi.encodeWithSignature("hotfix__mapTokensAndThresholds_registerCallbacks()")
        )
      });
      // mainchainBMproxy.upgradeToAndCall(
      //   newBMLogic, abi.encodeWithSignature(
      //       // function expose_mapTokensAndThresholds(
      //       //   address[] calldata mainchainTokens,
      //       //   address[] calldata roninTokens,
      //       //   TokenStandard[] calldata standards,
      //       //   uint256[][4] calldata thresholds
      //       // )
      //     "expose_mapTokensAndThresholds(address[],address[],uint8[],uint256[][4])",
      //     mainchainTokens,
      //     roninTokens,
      //     standards,
      //     thresholds
      //   )
      // );

      vm.startPrank(address(_multisigEth));
      assertTrue(mainchainBMproxy.implementation() == newBMLogic, "Mainchain BM Logic");
      vm.stopPrank();
    }

    // 2. Downgrade to previous version
    cheatBroadcast({
      from: _multisigEth,
      to: address(mainchainBMproxy),
      callValue: 0,
      callData: abi.encodeWithSignature(
        "upgradeTo(address)",
        prevBMLogic
      )
    });
  }

  function _postCheck() internal virtual override {
    console.log("Starting post-check".bold().cyan());

    super._postCheck();
  }
}
