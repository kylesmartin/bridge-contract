// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import { console } from "forge-std/console.sol";
import { StdStyle } from "forge-std/StdStyle.sol";
import { RoninBridgeManager } from "@ronin/contracts/ronin/gateway/RoninBridgeManager.sol";
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
import "@ronin/contracts/mainchain/MainchainBridgeManager.sol";
import "@ronin/contracts/mainchain/MainchainGatewayV3.sol";
import "@ronin/contracts/libraries/Proposal.sol";
import "@ronin/contracts/libraries/Ballot.sol";

import { MockSLP } from "@ronin/contracts/mocks/token/MockSLP.sol";
import { SLPDeploy } from "@ronin/script/contracts/token/SLPDeploy.s.sol";
import { MainchainBridgeAdminUtils } from "test/helpers/MainchainBridgeAdminUtils.t.sol";
import "@ronin/script/contracts/RoninBridgeManagerDeploy.s.sol";
import { DefaultContract } from "@fdk/utils/DefaultContract.sol";
import "./20240716-deploy-bridge-manager-helper.s.sol";
import "./20240716-helper.s.sol";
import "./wbtc-threshold.s.sol";
import { DefaultNetwork } from "@fdk/utils/DefaultNetwork.sol";

contract Migration__20240716_P2_UpgradeBridgeRoninchain is
  Migration__20240716_Helper,
  Migration__20240716_DeployRoninBridgeManagerHelper,
  Migration__MapToken_WBTC_Threshold
{
  ISharedArgument.SharedParameter _param;

  function setUp() public virtual override {
    super.setUp();
  }

  function run() public virtual onlyOn(DefaultNetwork.RoninMainnet.key()) {
    _currRoninBridgeManager = RoninBridgeManager(config.getAddressFromCurrentNetwork(Contract.RoninBridgeManager.key()));
    _newRoninBridgeManager = _deployRoninBridgeManager();

    _proposer = 0xe880802580a1fbdeF67ACe39D1B21c5b2C74f059;

    (address[] memory currGovernors,,) = _currRoninBridgeManager.getFullBridgeOperatorInfos();
    for (uint i = 0; i < currGovernors.length; i++) {
      _voters.push(currGovernors[i]);
    }

    _upgradeBridgeRoninchain();

    config.setAddress(network(), Contract.RoninBridgeManager.key(), address(_newRoninBridgeManager));
  }

  function _upgradeBridgeRoninchain() private {
    address bridgeRewardLogic = _deployLogic(Contract.BridgeReward.key());
    address bridgeSlashLogic = _deployLogic(Contract.BridgeSlash.key());
    address bridgeTrackingLogic = _deployLogic(Contract.BridgeTracking.key());
    address pauseEnforcerLogic = _deployLogic(Contract.RoninPauseEnforcer.key());
    address roninGatewayV3Logic = _deployLogic(Contract.RoninGatewayV3.key());

    address bridgeRewardProxy = config.getAddressFromCurrentNetwork(Contract.BridgeReward.key());
    address bridgeSlashProxy = config.getAddressFromCurrentNetwork(Contract.BridgeSlash.key());
    address bridgeTrackingProxy = config.getAddressFromCurrentNetwork(Contract.BridgeTracking.key());
    // address pauseEnforcerProxy = config.getAddressFromCurrentNetwork(Contract.RoninPauseEnforcer.key());
    address roninGatewayV3Proxy = config.getAddressFromCurrentNetwork(Contract.RoninGatewayV3.key());

    ISharedArgument.SharedParameter memory param;
    param.roninBridgeManager.callbackRegisters = new address[](1);
    param.roninBridgeManager.callbackRegisters[0] = config.getAddressFromCurrentNetwork(Contract.BridgeSlash.key());

    uint N = 16;
    address[] memory targets = new address[](N);
    uint256[] memory values = new uint256[](N);
    bytes[] memory calldatas = new bytes[](N);
    uint256[] memory gasAmounts = new uint256[](N);

    uint cCount;

    targets[cCount] = bridgeRewardProxy;
    calldatas[cCount++] =
      abi.encodeWithSignature("upgradeToAndCall(address,bytes)", bridgeRewardLogic, abi.encodeWithSelector(BridgeReward.initializeV2.selector));

    targets[cCount] = bridgeSlashProxy;
    calldatas[cCount++] = abi.encodeWithSignature("upgradeTo(address)", bridgeSlashLogic);

    targets[cCount] = bridgeTrackingProxy;
    calldatas[cCount++] = abi.encodeWithSignature("upgradeTo(address)", bridgeTrackingLogic);

    targets[cCount] = roninGatewayV3Proxy;
    calldatas[cCount++] = abi.encodeWithSignature("upgradeTo(address)", roninGatewayV3Logic);

    targets[cCount] = bridgeRewardProxy;
    calldatas[cCount++] =
      abi.encodeWithSignature("functionDelegateCall(bytes)", (abi.encodeWithSignature("setContract(uint8,address)", 11, address(_newRoninBridgeManager))));

    targets[cCount] = bridgeSlashProxy;
    calldatas[cCount++] =
      abi.encodeWithSignature("functionDelegateCall(bytes)", (abi.encodeWithSignature("setContract(uint8,address)", 11, address(_newRoninBridgeManager))));

    targets[cCount] = bridgeTrackingProxy;
    calldatas[cCount++] =
      abi.encodeWithSignature("functionDelegateCall(bytes)", (abi.encodeWithSignature("setContract(uint8,address)", 11, address(_newRoninBridgeManager))));

    targets[cCount] = roninGatewayV3Proxy;
    calldatas[cCount++] =
      abi.encodeWithSignature("functionDelegateCall(bytes)", (abi.encodeWithSignature("setContract(uint8,address)", 11, address(_newRoninBridgeManager))));

    {
      address[] memory roninTokens = new address[](1);
      address[] memory mainchainTokens = new address[](1);
      uint256[] memory chainIds = new uint256[](1);
      TokenStandard[] memory standards = new TokenStandard[](1);

      roninTokens[0] = _wbtcRoninToken;
      mainchainTokens[0] = _wbtcMainchainToken;
      chainIds[0] = config.getNetworkData(config.getCompanionNetwork(network())).chainId;
      standards[0] = TokenStandard.ERC20;

      address[] memory mainchainTokensToSetMinThreshold = new address[](1);
      uint256[] memory minThresholds = new uint256[](1);
      mainchainTokensToSetMinThreshold[0] = _wbtcMainchainToken;
      minThresholds[0] = _wbtcMinThreshold;

      targets[cCount] = roninGatewayV3Proxy;
      calldatas[cCount++] =
        abi.encodeWithSignature("functionDelegateCall(bytes)", abi.encodeCall(IRoninGatewayV3.mapTokens, (roninTokens, mainchainTokens, chainIds, standards)));

      targets[cCount] = roninGatewayV3Proxy;
      calldatas[cCount++] = abi.encodeWithSignature(
        "functionDelegateCall(bytes)", abi.encodeCall(MinimumWithdrawal.setMinimumThresholds, (mainchainTokensToSetMinThreshold, minThresholds))
      );
    }

    targets[cCount] = bridgeRewardProxy;
    calldatas[cCount++] = abi.encodeWithSignature("changeAdmin(address)", address(_newRoninBridgeManager));

    targets[cCount] = bridgeSlashProxy;
    calldatas[cCount++] = abi.encodeWithSignature("changeAdmin(address)", address(_newRoninBridgeManager));

    targets[cCount] = bridgeTrackingProxy;
    calldatas[cCount++] = abi.encodeWithSignature("changeAdmin(address)", address(_newRoninBridgeManager));

    targets[cCount] = roninGatewayV3Proxy;
    calldatas[cCount++] = abi.encodeWithSignature("changeAdmin(address)", address(_newRoninBridgeManager));

    targets[cCount] = address(_newRoninBridgeManager);
    calldatas[cCount++] = abi.encodeWithSignature(
      "functionDelegateCall(bytes)", (abi.encodeWithSignature("registerCallbacks(address[])", param.roninBridgeManager.callbackRegisters))
    );

    targets[cCount] = address(_newRoninBridgeManager);
    calldatas[cCount++] = abi.encodeWithSignature("changeAdmin(address)", address(_newRoninBridgeManager));

    assertEq(cCount, N);

    for (uint i; i < N; ++i) {
      gasAmounts[i] = 1_000_000;
    }

    LegacyProposalDetail memory proposal;
    proposal.nonce = _currRoninBridgeManager.round(block.chainid) + 1;
    proposal.chainId = block.chainid;
    proposal.expiryTimestamp = block.timestamp + 14 days;
    proposal.targets = targets;
    proposal.values = values;
    proposal.calldatas = calldatas;
    proposal.gasAmounts = gasAmounts;

    _helperProposeForCurrentNetwork(proposal);
    _helperVoteForCurrentNetwork(proposal);
  }
}
