// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import { console } from "forge-std/console.sol";
import { ITransparentUpgradeableProxyV2 } from "script/interfaces/ITransparentUpgradeableProxyV2.sol";
import { BasePostCheck } from "../../BasePostCheck.s.sol";
import { IBridgeManager } from "@ronin/contracts/interfaces/bridge/IBridgeManager.sol";
import { IRoninBridgeManager } from "script/interfaces/IRoninBridgeManager.sol";
import { IMainchainBridgeManager } from "script/interfaces/IMainchainBridgeManager.sol";
import { TContract, Contract } from "script/utils/Contract.sol";
import { TNetwork, Network } from "script/utils/Network.sol";
import { LibArray } from "script/shared/libraries/LibArray.sol";
import { LibCompanionNetwork } from "script/shared/libraries/LibCompanionNetwork.sol";
import { Ballot, Proposal, GlobalProposal, LibProposal } from "script/shared/libraries/LibProposal.sol";
import { LibProxy } from "@fdk/libraries/LibProxy.sol";
import { DefaultNetwork } from "@fdk/utils/DefaultNetwork.sol";
import { IRuntimeConfig } from "@fdk/interfaces/configs/IRuntimeConfig.sol";

abstract contract PostCheck_BridgeManager_Proposal is BasePostCheck {
  using LibArray for *;
  using LibProxy for *;
  using LibProposal for *;
  using LibCompanionNetwork for *;

  /// @dev The default expiry time for the proposal.
  uint256 private proposalDuration = 20 minutes;
  /// @dev The vote weight of the bridge operators.
  uint96[] private vws = [100, 100];
  /// @dev The governor of the bridge operators.
  address[] private gvs = [makeAddr("gv-1"), makeAddr("gv-2")];
  /// @dev The bridge operators.
  address[] private ops = [makeAddr("op-1"), makeAddr("op-2")];

  function _validate_BridgeManager_Proposal() internal {
    validate_RevertIf_NonGovernor_VoteProposal();
    validate_RevertIf_NotEnoughSignatures_RelayUpgradeProposal();
    validate_RevertIf_NonGovernor_CreateProposal();
    validate_canExecuteUpgradeItself();
    validate_relayUpgradeProposal();
    validate_ProposeGlobalProposalAndRelay_addBridgeOperator();
    validate_proposeAndRelay_addBridgeOperator();
    validate_canExecuteUpgradeSingleProposal();
    validate_canExecuteUpgradeAllOneProposal();
  }

  function validate_RevertIf_NonGovernor_VoteProposal()
    private
    onlyOnRoninNetworkOrLocal
    onPostCheck("validate_RevertIf_NotEnoughSignature_RelayUpgradeProposal")
  {
    address nonGovernor = makeAddr("non-governor");

    address[] memory targets = ronBM.toSingletonArray();
    uint256[] memory values = uint256(0).toSingletonArray();
    bytes[] memory calldatas = abi.encodeCall(
      ITransparentUpgradeableProxyV2.functionDelegateCall, (abi.encodeCall(IBridgeManager.addBridgeOperators, (vws, gvs, ops)))
    ).toSingletonArray();
    uint256[] memory gasAmounts = uint256(1_000_000).toSingletonArray();

    address[] memory governors = IRoninBridgeManager(ronBM).getGovernors();

    Proposal.ProposalDetail memory proposal = LibProposal.createProposal({
      bm: ronBM,
      expiry: block.timestamp + proposalDuration,
      targets: targets,
      values: values,
      callDatas: calldatas,
      gasAmounts: gasAmounts,
      nonce: IRoninBridgeManager(ronBM).round(0) + 1
    });

    vm.prank(governors[0]);
    IRoninBridgeManager(ronBM).proposeProposalForCurrentNetwork(
      proposal.expiryTimestamp, proposal.executor, proposal.targets, proposal.values, proposal.calldatas, proposal.gasAmounts, Ballot.VoteType.For
    );

    vm.prank(nonGovernor);
    vm.expectRevert();
    IRoninBridgeManager(ronBM).castProposalVoteForCurrentNetwork(proposal, Ballot.VoteType.For);

    vm.prank(nonGovernor);
    vm.expectRevert();
    IRoninBridgeManager(ronBM).castProposalVoteForCurrentNetwork(proposal, Ballot.VoteType.Against);
  }

  function validate_RevertIf_NotEnoughSignatures_RelayUpgradeProposal()
    private
    onlyOnRoninNetworkOrLocal
    onPostCheck("validate_RevertIf_NotEnoughSignature_RelayUpgradeProposal")
  {
    TNetwork currNetwork = vme.getCurrentNetwork();
    (, TNetwork companionNetwork) = currNetwork.companionNetworkData();

    switchTo(companionNetwork);

    uint256 snapshotId = vm.snapshot();

    overrideMockBOs(ethBM);

    address[] memory targets = new address[](2);
    uint256[] memory values = new uint256[](2);
    uint256[] memory gasAmounts = new uint256[](2);
    bytes[] memory calldatas = new bytes[](2);
    address[] memory logics = new address[](2);

    targets[0] = ethBM;
    targets[1] = ethGW;

    logics[0] = _deployLogic(Contract.MainchainBridgeManager.key());
    logics[1] = _deployLogic(Contract.MainchainGatewayV3.key());

    calldatas[0] = abi.encodeCall(ITransparentUpgradeableProxyV2.upgradeTo, (logics[0]));
    calldatas[1] = abi.encodeCall(ITransparentUpgradeableProxyV2.upgradeTo, (logics[1]));

    gasAmounts[0] = 1_000_000;
    gasAmounts[1] = 1_000_000;

    Proposal.ProposalDetail memory proposal = LibProposal.createProposal({
      bm: ethBM,
      expiry: block.timestamp + proposalDuration,
      targets: targets,
      values: values,
      callDatas: calldatas,
      gasAmounts: gasAmounts,
      nonce: IMainchainBridgeManager(ethBM).round(block.chainid) + 1
    });

    Signature[] memory signatures = proposal.generateSignatures(mockGvPKs, Ballot.VoteType.For);

    uint256 minVW = IMainchainBridgeManager(ethBM).minimumVoteWeight();
    uint256 defaultVW = IMainchainBridgeManager(ethBM).getTotalWeight() / IMainchainBridgeManager(ethBM).totalBridgeOperator();
    uint256 minRequiredSig = minVW / defaultVW + 1;
    assertTrue(minRequiredSig > 1, "Invalid Setup: minRequiredSig <= 1");

    uint256 unmetSigCount = minRequiredSig - 1;

    assembly {
      mstore(signatures, unmetSigCount)
    }

    Ballot.VoteType[] memory _supports = new Ballot.VoteType[](signatures.length);

    vm.prank(mockGvs[0]);
    vm.expectRevert();
    IMainchainBridgeManager(ethBM).relayProposal(proposal, _supports, signatures);

    assertTrue(vm.revertTo(snapshotId), "Cannot revert to snapshot id");
    _switchBackToRoninFork(currNetwork);
  }

  function validate_RevertIf_NonGovernor_CreateProposal() private onlyOnRoninNetworkOrLocal onPostCheck("validate_RevertIf_NonGovernor_CreateProposal") {
    address nonGovernor = makeAddr("non-governor");

    address[] memory targets = ronBM.toSingletonArray();
    uint256[] memory values = uint256(0).toSingletonArray();
    bytes[] memory calldatas = abi.encodeCall(
      ITransparentUpgradeableProxyV2.functionDelegateCall, (abi.encodeCall(IBridgeManager.addBridgeOperators, (vws, gvs, ops)))
    ).toSingletonArray();
    uint256[] memory gasAmounts = uint256(1_000_000).toSingletonArray();

    vm.expectRevert();
    vm.prank(nonGovernor);
    IRoninBridgeManager(ronBM).propose(block.chainid, block.timestamp + proposalDuration, address(0x0), targets, values, calldatas, gasAmounts);

    Proposal.ProposalDetail memory proposal = LibProposal.createProposal({
      bm: ronBM,
      expiry: block.timestamp + proposalDuration,
      targets: targets,
      values: values,
      callDatas: calldatas,
      gasAmounts: gasAmounts,
      nonce: IRoninBridgeManager(ronBM).round(0) + 1
    });

    vm.prank(nonGovernor);
    vm.expectRevert();
    IRoninBridgeManager(ronBM).proposeProposalForCurrentNetwork(
      proposal.expiryTimestamp, proposal.executor, proposal.targets, proposal.values, proposal.calldatas, proposal.gasAmounts, Ballot.VoteType.For
    );
  }

  function validate_proposeAndRelay_addBridgeOperator() private onlyOnRoninNetworkOrLocal onPostCheck("validate_proposeAndRelay_addBridgeOperator") {
    // Cheat add gv
    cheatAddOverWeightedGovernor(ronBM);

    address[] memory targets = ronBM.toSingletonArray();
    uint256[] memory values = uint256(0).toSingletonArray();
    bytes[] memory calldatas = abi.encodeCall(
      ITransparentUpgradeableProxyV2.functionDelegateCall, (abi.encodeCall(IBridgeManager.addBridgeOperators, (vws, gvs, ops)))
    ).toSingletonArray();
    uint256[] memory gasAmounts = uint256(1_000_000).toSingletonArray();

    uint256 ronChainId = block.chainid;

    Proposal.ProposalDetail memory proposal = LibProposal.createProposal({
      bm: ronBM,
      expiry: block.timestamp + proposalDuration,
      targets: targets,
      values: values,
      callDatas: calldatas,
      gasAmounts: gasAmounts,
      nonce: IRoninBridgeManager(ronBM).round(0) + 1
    });

    vm.prank(cheatGv);
    IRoninBridgeManager(ronBM).propose(ronChainId, block.timestamp + proposalDuration, address(0x0), targets, values, calldatas, gasAmounts);

    {
      TNetwork currNetwork = vme.getCurrentNetwork();
      (, TNetwork companionNetwork) = currNetwork.companionNetworkData();

      switchTo(companionNetwork);

      uint256 snapshotId = vm.snapshot();

      // Cheat add gv
      cheatAddOverWeightedGovernor(ethBM);

      targets = ethBM.toSingletonArray();

      proposal = LibProposal.createProposal({
        bm: ethBM,
        expiry: block.timestamp + proposalDuration,
        targets: targets,
        values: proposal.values,
        callDatas: proposal.calldatas,
        gasAmounts: proposal.gasAmounts,
        nonce: IMainchainBridgeManager(ethBM).round(block.chainid) + 1
      });

      Signature[] memory signatures = proposal.generateSignatures(cheatGvPK.toSingletonArray(), Ballot.VoteType.For);
      Ballot.VoteType[] memory _supports = new Ballot.VoteType[](signatures.length);

      uint256 minForVW = IMainchainBridgeManager(ethBM).minimumVoteWeight();
      uint256 totalForVW = IMainchainBridgeManager(ethBM).getGovernorWeight(cheatGv);

      console.log("Total for vote weight:", totalForVW);
      console.log("Minimum for vote weight:", minForVW);

      vm.prank(cheatGv);
      IMainchainBridgeManager(ethBM).relayProposal(proposal, _supports, signatures);
      for (uint256 i; i < gvs.length; ++i) {
        assertTrue(IMainchainBridgeManager(ethBM).isBridgeOperator(ops[i]), "isBridgeOperator == false");
      }

      assertTrue(vm.revertTo(snapshotId), "Cannot revert to snapshot id");
      _switchBackToRoninFork(currNetwork);
    }
  }

  function validate_relayUpgradeProposal() private onlyOnRoninNetworkOrLocal onPostCheck("validate_relayUpgradeProposal") {
    TNetwork currNetwork = vme.getCurrentNetwork();
    (, TNetwork companionNetwork) = currNetwork.companionNetworkData();

    switchTo(companionNetwork);

    uint256 snapshotId = vm.snapshot();

    // Cheat add gv
    {
      cheatAddOverWeightedGovernor(ethBM);

      address[] memory targets = new address[](2);
      uint256[] memory values = new uint256[](2);
      uint256[] memory gasAmounts = new uint256[](2);
      bytes[] memory calldatas = new bytes[](2);
      address[] memory logics = new address[](2);

      targets[0] = ethBM;
      targets[1] = ethGW;

      logics[0] = _deployLogic(Contract.MainchainBridgeManager.key());
      logics[1] = _deployLogic(Contract.MainchainGatewayV3.key());

      calldatas[0] = abi.encodeCall(ITransparentUpgradeableProxyV2.upgradeTo, (logics[0]));
      calldatas[1] = abi.encodeCall(ITransparentUpgradeableProxyV2.upgradeTo, (logics[1]));

      gasAmounts[0] = 1_000_000;
      gasAmounts[1] = 1_000_000;

      Proposal.ProposalDetail memory proposal = LibProposal.createProposal({
        bm: ethBM,
        expiry: block.timestamp + proposalDuration,
        targets: targets,
        values: values,
        callDatas: calldatas,
        gasAmounts: gasAmounts,
        nonce: IMainchainBridgeManager(ethBM).round(block.chainid) + 1
      });

      Signature[] memory signatures = proposal.generateSignatures(cheatGvPK.toSingletonArray(), Ballot.VoteType.For);
      Ballot.VoteType[] memory _supports = new Ballot.VoteType[](signatures.length);

      uint256 minForVW = IMainchainBridgeManager(ethBM).minimumVoteWeight();
      uint256 totalForVW = IMainchainBridgeManager(ethBM).getGovernorWeight(cheatGv);
      console.log("Total for vote weight:", totalForVW);
      console.log("Minimum for vote weight:", minForVW);

      vm.prank(cheatGv);
      IMainchainBridgeManager(ethBM).relayProposal(proposal, _supports, signatures);

      assertEq(ethBM.getProxyImplementation(), logics[0], "MainchainBridgeManager logic is not upgraded");
      assertEq(ethGW.getProxyImplementation(), logics[1], "MainchainGatewayV3 logic is not upgraded");
    }

    assertTrue(vm.revertTo(snapshotId), "Cannot revert to snapshot id");
    _switchBackToRoninFork(currNetwork);
  }

  function validate_ProposeGlobalProposalAndRelay_addBridgeOperator()
    private
    onlyOnRoninNetworkOrLocal
    onPostCheck("validate_ProposeGlobalProposalAndRelay_addBridgeOperator")
  {
    cheatAddOverWeightedGovernor(ronBM);

    GlobalProposal.TargetOption[] memory targetOptions = new GlobalProposal.TargetOption[](1);
    targetOptions[0] = GlobalProposal.TargetOption.BridgeManager;

    GlobalProposal.GlobalProposalDetail memory globalProposal = LibProposal.createGlobalProposal({
      expiry: block.timestamp + proposalDuration,
      targetOpts: targetOptions,
      values: uint256(0).toSingletonArray(),
      callDatas: abi.encodeCall(ITransparentUpgradeableProxyV2.functionDelegateCall, (abi.encodeCall(IBridgeManager.addBridgeOperators, (vws, gvs, ops))))
        .toSingletonArray(),
      gasAmounts: uint256(1_000_000).toSingletonArray(),
      nonce: IRoninBridgeManager(ronBM).round(0) + 1
    });

    Signature[] memory signatures;
    Ballot.VoteType[] memory _supports;
    {
      signatures = globalProposal.generateSignaturesGlobal(cheatGvPK.toSingletonArray(), Ballot.VoteType.For);
      _supports = new Ballot.VoteType[](signatures.length);

      vm.prank(cheatGv);
      IRoninBridgeManager(ronBM).proposeGlobalProposalStructAndCastVotes(globalProposal, _supports, signatures);
    }

    // Check if the proposal is voted
    assertEq(IRoninBridgeManager(ronBM).globalProposalVoted(globalProposal.nonce, cheatGv), true);
    for (uint256 i; i < gvs.length; ++i) {
      assertEq(IRoninBridgeManager(ronBM).isBridgeOperator(ops[i]), true, "isBridgeOperator == false");
    }

    {
      TNetwork currNetwork = vme.getCurrentNetwork();
      (, TNetwork companionNetwork) = currNetwork.companionNetworkData();

      switchTo(companionNetwork);

      uint256 snapshotId = vm.snapshot();

      cheatAddOverWeightedGovernor(ethBM);

      vm.prank(cheatGv);
      IMainchainBridgeManager(ethBM).relayGlobalProposal(globalProposal, _supports, signatures);

      for (uint256 i; i < gvs.length; ++i) {
        assertTrue(IMainchainBridgeManager(ethBM).isBridgeOperator(ops[i]), "isBridgeOperator == false");
      }

      assertTrue(vm.revertTo(snapshotId), "Cannot revert to snapshot id");
      _switchBackToRoninFork(currNetwork);
    }
  }

  function validate_canExecuteUpgradeSingleProposal() private onlyOnRoninNetworkOrLocal onPostCheck("validate_canExecuteUpgradeSingleProposal") {
    TContract[] memory contractTypes = new TContract[](4);
    contractTypes[0] = Contract.BridgeSlash.key();
    contractTypes[1] = Contract.BridgeReward.key();
    contractTypes[2] = Contract.BridgeTracking.key();
    contractTypes[3] = Contract.RoninGatewayV3.key();

    address[] memory targets = new address[](contractTypes.length);
    for (uint256 i; i < contractTypes.length; ++i) {
      targets[i] = loadContract(contractTypes[i]);
    }

    for (uint256 i; i < targets.length; ++i) {
      console.log("Upgrading contract:", vm.getLabel(targets[i]));
      _upgradeProxy(contractTypes[i]);
    }
  }

  function validate_canExecuteUpgradeAllOneProposal() private onlyOnRoninNetworkOrLocal onPostCheck("validate_canExecuteUpgradeAllOneProposal") {
    TContract[] memory contractTypes = new TContract[](4);
    contractTypes[0] = Contract.BridgeSlash.key();
    contractTypes[1] = Contract.BridgeReward.key();
    contractTypes[2] = Contract.BridgeTracking.key();
    contractTypes[3] = Contract.RoninGatewayV3.key();

    address[] memory targets = new address[](contractTypes.length);
    for (uint256 i; i < contractTypes.length; ++i) {
      targets[i] = loadContract(contractTypes[i]);
    }

    address[] memory logics = new address[](targets.length);
    for (uint256 i; i < targets.length; ++i) {
      console.log("Deploy contract logic:", vm.getLabel(targets[i]));
      logics[i] = _deployLogic(contractTypes[i]);
    }

    // Upgrade all contracts with proposal
    bytes[] memory calldatas = new bytes[](targets.length);
    for (uint256 i; i < targets.length; ++i) {
      calldatas[i] = abi.encodeCall(ITransparentUpgradeableProxyV2.upgradeTo, (logics[i]));
    }

    Proposal.ProposalDetail memory proposal = LibProposal.createProposal({
      bm: ronBM,
      expiry: block.timestamp + proposalDuration,
      targets: targets,
      values: uint256(0).repeat(targets.length),
      callDatas: calldatas,
      gasAmounts: uint256(1_000_000).repeat(targets.length),
      nonce: IRoninBridgeManager(ronBM).round(block.chainid) + 1
    });

    IRoninBridgeManager(ronBM).executeProposal(proposal);
  }

  function validate_canExecuteUpgradeItself() private onlyOnRoninNetworkOrLocal onPostCheck("validate_canExecuteUpgradeItself") {
    TContract[] memory contractTypes = new TContract[](1);
    contractTypes[0] = Contract.RoninBridgeManager.key();

    address[] memory targets = new address[](contractTypes.length);
    for (uint256 i; i < contractTypes.length; ++i) {
      targets[i] = loadContract(contractTypes[i]);
    }

    address[] memory logics = new address[](targets.length);
    for (uint256 i; i < targets.length; ++i) {
      console.log("Deploy contract logic:", vm.getLabel(targets[i]));
      logics[i] = _deployLogic(contractTypes[i]);
    }

    // Upgrade all contracts with proposal
    bytes[] memory calldatas = new bytes[](targets.length);
    for (uint256 i; i < targets.length; ++i) {
      calldatas[i] = abi.encodeCall(ITransparentUpgradeableProxyV2.upgradeTo, (logics[i]));
    }

    Proposal.ProposalDetail memory proposal = LibProposal.createProposal({
      bm: ronBM,
      expiry: block.timestamp + proposalDuration,
      targets: targets,
      values: uint256(0).repeat(targets.length),
      callDatas: calldatas,
      gasAmounts: uint256(1_000_000).repeat(targets.length),
      nonce: IRoninBridgeManager(ronBM).round(block.chainid) + 1
    });

    IRoninBridgeManager(ronBM).executeProposal(proposal);
  }

  function _switchBackToRoninFork(TNetwork roninNetwork) internal {
    uint originForkBlockNumber = vme.getRuntimeConfig().forkBlockNumber;
    uint roninForkId = vme.getForkId(roninNetwork, originForkBlockNumber);
    vme.switchTo(roninForkId);
  }
}
