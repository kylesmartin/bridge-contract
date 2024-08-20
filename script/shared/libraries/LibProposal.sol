// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import { ECDSA } from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import { Vm } from "forge-std/Vm.sol";
import { StdCheats } from "forge-std/StdCheats.sol";
import { console } from "forge-std/console.sol";
import { IGeneralConfigExtended } from "script/interfaces/IGeneralConfigExtended.sol";
import { TNetwork, Network } from "script/utils/Network.sol";
import { Contract } from "script/utils/Contract.sol";
import { DefaultNetwork } from "@fdk/utils/DefaultNetwork.sol";
import { LibSharedAddress } from "@fdk/libraries/LibSharedAddress.sol";
import { Proposal } from "@ronin/contracts/libraries/Proposal.sol";
import { GlobalProposal } from "@ronin/contracts/libraries/GlobalProposal.sol";
import { Ballot } from "@ronin/contracts/libraries/Ballot.sol";
import { IRoninBridgeManager } from "script/interfaces/IRoninBridgeManager.sol";
import { IMainchainBridgeManager } from "script/interfaces/IMainchainBridgeManager.sol";
import { SignatureConsumer } from "@ronin/contracts/interfaces/consumers/SignatureConsumer.sol";
import { LibArray } from "./LibArray.sol";
import { LibStorage } from "./LibStorage.sol";
import { LibProxy } from "@fdk/libraries/LibProxy.sol";
import { LibCompanionNetwork } from "./LibCompanionNetwork.sol";
import { LibErrorHandler } from "@fdk/libraries/LibErrorHandler.sol";
import { VoteStatusConsumer } from "@ronin/contracts/interfaces/consumers/VoteStatusConsumer.sol";
import { IRuntimeConfig } from "@fdk/interfaces/configs/IRuntimeConfig.sol";

library LibProposal {
  using LibArray for *;
  using LibProxy for *;
  using ECDSA for bytes32;
  using LibErrorHandler for bool;
  using LibCompanionNetwork for *;
  using Proposal for Proposal.ProposalDetail;
  using GlobalProposal for GlobalProposal.GlobalProposalDetail;

  error ErrProposalOutOfGas(uint256 chainId, bytes4 msgSig, uint256 gasUsed);

  uint256 internal constant DEFAULT_PROPOSAL_GAS = 1_000_000;
  Vm private constant vm = Vm(LibSharedAddress.VM);
  IGeneralConfigExtended private constant config = IGeneralConfigExtended(LibSharedAddress.CONFIG);

  modifier preserveState() {
    uint256 snapshotId = vm.snapshot();
    _;
    bool reverted = vm.revertTo(snapshotId);
    require(reverted, string.concat("Cannot revert to snapshot id: ", vm.toString(snapshotId)));
  }

  function getBridgeManagerDomain() internal view returns (bytes32) {
    uint256 chainId;
    TNetwork currentNetwork = config.getCurrentNetwork();
    if (currentNetwork == Network.EthMainnet.key() || currentNetwork == Network.Goerli.key() || currentNetwork == Network.Sepolia.key()) {
      chainId = currentNetwork.companionChainId();
    } else {
      chainId = block.chainid;
    }
    return keccak256(
      abi.encode(
        keccak256("EIP712Domain(string name,string version,bytes32 salt)"),
        keccak256("BridgeManager"), // name hash
        keccak256("3"), // version hash
        keccak256(abi.encode("BRIDGE_MANAGER", chainId)) // salt
      )
    );
  }

  function createProposal(
    address manager,
    uint256 nonce,
    uint256 expiryTimestamp,
    address[] memory targets,
    uint256[] memory values,
    bytes[] memory calldatas,
    uint256[] memory gasAmounts
  ) internal returns (Proposal.ProposalDetail memory proposal) {
    verifyProposalGasAmount(manager, targets, values, calldatas, gasAmounts);

    proposal = Proposal.ProposalDetail({
      nonce: nonce,
      chainId: block.chainid,
      expiryTimestamp: expiryTimestamp,
      targets: targets,
      executor: address(0x0),
      values: values,
      calldatas: calldatas,
      gasAmounts: gasAmounts
    });
  }

  function createGlobalProposal(
    uint256 nonce,
    uint256 expiryTimestamp,
    uint256[] memory values,
    bytes[] memory calldatas,
    uint256[] memory gasAmounts,
    GlobalProposal.TargetOption[] memory targetOptions
  ) internal returns (GlobalProposal.GlobalProposalDetail memory proposal) {
    verifyGlobalProposalGasAmount(values, calldatas, gasAmounts, targetOptions);
    proposal = GlobalProposal.GlobalProposalDetail({
      nonce: nonce,
      expiryTimestamp: expiryTimestamp,
      targetOptions: targetOptions,
      values: values,
      executor: address(0x0),
      calldatas: calldatas,
      gasAmounts: gasAmounts
    });
  }

  function executeProposal(IRoninBridgeManager manager, Proposal.ProposalDetail memory proposal) internal {
    Ballot.VoteType support = Ballot.VoteType.For;
    address[] memory governors = manager.getGovernors();

    bool shouldPrankOnly = config.isPostChecking();
    address governor0 = governors[0];

    if (shouldPrankOnly) {
      vm.prank(governor0);
    } else {
      vm.broadcast(governor0);
    }
    manager.proposeProposalForCurrentNetwork(
      proposal.expiryTimestamp, proposal.executor, proposal.targets, proposal.values, proposal.calldatas, proposal.gasAmounts, support
    );

    voteFor(manager, proposal);
  }

  function voteFor(IRoninBridgeManager manager, Proposal.ProposalDetail memory proposal) internal {
    Ballot.VoteType support = Ballot.VoteType.For;
    address[] memory governors = manager.getGovernors();
    bool shouldPrankOnly = config.isPostChecking();

    uint256 totalGas = proposal.gasAmounts.sum();
    // 20% more gas for each governor
    totalGas += totalGas * 20_00 / 100_00;
    // if totalGas is less than DEFAULT_PROPOSAL_GAS, set it to 120% of DEFAULT_PROPOSAL_GAS
    if (totalGas < DEFAULT_PROPOSAL_GAS) totalGas = DEFAULT_PROPOSAL_GAS * 120_00 / 100_00;

    for (uint256 i = 1; i < governors.length; ++i) {
      (VoteStatusConsumer.VoteStatus status,,,,) = manager.vote(block.chainid, proposal.nonce);
      if (status != VoteStatusConsumer.VoteStatus.Pending) break;

      address governor = governors[i];
      if (shouldPrankOnly) {
        vm.prank(governor);
      } else {
        vm.broadcast(governor);
      }

      manager.castProposalVoteForCurrentNetwork{ gas: totalGas }(proposal, support);
    }
  }

  function verifyGlobalProposalGasAmount(
    uint256[] memory values,
    bytes[] memory calldatas,
    uint256[] memory gasAmounts,
    GlobalProposal.TargetOption[] memory targetOptions
  ) internal {
    address manager;
    address companionManager;
    TNetwork currentNetwork = config.getCurrentNetwork();
    TNetwork companionNetwork = config.getCompanionNetwork(currentNetwork);
    address[] memory roninTargets = new address[](targetOptions.length);
    address[] memory mainchainTargets = new address[](targetOptions.length);

    if (currentNetwork == Network.EthMainnet.key() || currentNetwork == Network.Goerli.key() || currentNetwork == Network.Sepolia.key()) {
      manager = config.getAddress(currentNetwork, Contract.MainchainBridgeManager.key());
      companionManager = config.getAddress(companionNetwork, Contract.RoninBridgeManager.key());
    } else {
      manager = config.getAddress(currentNetwork, Contract.RoninBridgeManager.key());
      companionManager = config.getAddress(companionNetwork, Contract.MainchainBridgeManager.key());
    }

    for (uint256 i; i < roninTargets.length; i++) {
      roninTargets[i] = resolveRoninTarget(targetOptions[i]);
      mainchainTargets[i] = resolveMainchainTarget(targetOptions[i]);
    }

    // Verify gas amount for ronin targets
    verifyProposalGasAmount(manager, roninTargets, values, calldatas, gasAmounts);

    // Verify gas amount for mainchain targets
    verifyMainchainProposalGasAmount(companionNetwork, companionManager, mainchainTargets, values, calldatas, gasAmounts);
  }

  function verifyMainchainProposalGasAmount(
    TNetwork companionNetwork,
    address mainchainManager,
    address[] memory mainchainTargets,
    uint256[] memory values,
    bytes[] memory calldatas,
    uint256[] memory gasAmounts
  ) internal preserveState {
    TNetwork currentNetwork = config.getCurrentNetwork();

    config.createFork(companionNetwork);
    config.switchTo(companionNetwork);

    uint256 snapshotId = vm.snapshot();

    for (uint256 i; i < mainchainTargets.length; i++) {
      vm.deal(mainchainManager, values[i]);
      vm.prank(mainchainManager);

      uint256 gasUsed = gasleft();
      (bool success, bytes memory returnOrRevertData) = mainchainTargets[i].call{ value: values[i], gas: gasAmounts[i] }(calldatas[i]);

      gasUsed = gasUsed - gasleft();

      if (success) {
        console.log("Call", i, ": gasUsed", gasUsed);
      } else {
        console.log("Call", i, unicode": reverted. ❗ GasUsed", gasUsed);
      }
      success.handleRevert(bytes4(calldatas[i]), returnOrRevertData);

      if (gasUsed > gasAmounts[i]) revert ErrProposalOutOfGas(block.chainid, bytes4(calldatas[i]), gasUsed);
    }

    bool reverted = vm.revertTo(snapshotId);
    require(reverted, string.concat("Cannot revert to snapshot id: ", vm.toString(snapshotId)));

    IRuntimeConfig.Option memory opt;
    opt = config.getRuntimeConfig();

    uint originForkBlockNumber = opt.forkBlockNumber;
    uint roninForkId = config.getForkId(currentNetwork, originForkBlockNumber);
    config.switchTo(roninForkId);
  }

  function verifyProposalGasAmount(
    address governance,
    address[] memory targets,
    uint256[] memory values,
    bytes[] memory calldatas,
    uint256[] memory gasAmounts
  ) internal preserveState {
    for (uint256 i; i < targets.length; i++) {
      vm.deal(governance, values[i]);
      vm.prank(governance);

      uint256 gasUsed = gasleft();

      (bool success, bytes memory returnOrRevertData) = targets[i].call{ value: values[i], gas: gasAmounts[i] }(calldatas[i]);
      gasUsed = gasUsed - gasleft();

      if (success) {
        console.log("Call", i, ": gasUsed", gasUsed);
      } else {
        console.log("Call", i, unicode": reverted. ❗ GasUsed", gasUsed);
      }
      success.handleRevert(bytes4(calldatas[i]), returnOrRevertData);

      if (gasUsed > gasAmounts[i]) revert ErrProposalOutOfGas(block.chainid, bytes4(calldatas[i]), gasUsed);
    }
  }

  function verifyProposalExecutionMainchain(
    address governance,
    Proposal.ProposalDetail memory proposal
  ) internal {
    address cheatPowerGov = 0x19614c50b0d13399A1533Fc1d3c1AD980A249aEa; // cheating pk, do not use in production
    uint256 cheatingPowerGovPk = 0x677911d1450076499cfe00fa1090c00c6ed7338fb5acfdef663a8fbde551d461; // cheating pk, do not use in production
    vm.label(cheatPowerGov, "CheatPowerGovernor");

    uint256[] memory cheatingPks = new uint256[](1);
    cheatingPks[0] = cheatingPowerGovPk;

    uint256 $$_governorWeightMap_Slot = uint256(0xc648703095712c0419b6431ae642c061f0a105ac2d7c3d9604061ef4ebc38300) + 2;
    bytes32 $$_governorWeight_Slot = LibStorage.getMappingElementSlotIndex(cheatPowerGov, uint256($$_governorWeightMap_Slot));

    vm.store(governance, $$_governorWeight_Slot, bytes32(uint256(uint96(100*1000))));

    {
      Ballot.VoteType[] memory supports_ = new Ballot.VoteType[](1);
      SignatureConsumer.Signature[] memory sigs_ = new SignatureConsumer.Signature[](1);
      supports_[0] = Ballot.VoteType.For;

      sigs_ = generateSignatures(proposal, cheatingPks, supports_[0]);

      if (proposal.executor == address(0)) {
        vm.prank(cheatPowerGov);
      } else {
        vm.prank(proposal.executor);
      }
      IMainchainBridgeManager(governance).relayProposal(proposal, supports_, sigs_);
    }
  }

  function verifyProposalExecutionMainchain(
    address governance,
    Proposal.ProposalDetail memory proposal,
    bool shouldRevertState
  ) internal {
    uint256 snapshotId;
    if (shouldRevertState) {
      snapshotId = vm.snapshot();
    }

    verifyProposalExecutionMainchain(governance, proposal);

    if (shouldRevertState) {
      bool revertSuccess = vm.revertTo(snapshotId);
      require(revertSuccess, "Cannot revert to snapshot id");
    }
  }

  function generateSignatures(
    Proposal.ProposalDetail memory proposal,
    uint256[] memory signerPKs,
    Ballot.VoteType support
  ) internal view returns (SignatureConsumer.Signature[] memory sigs) {
    return generateSignaturesFor(proposal.hash(), signerPKs, support);
  }

  function generateSignaturesGlobal(
    GlobalProposal.GlobalProposalDetail memory proposal,
    uint256[] memory signerPKs,
    Ballot.VoteType support
  ) internal view returns (SignatureConsumer.Signature[] memory sigs) {
    return generateSignaturesFor(proposal.hash(), signerPKs, support);
  }

  function generateSignaturesFor(
    bytes32 proposalHash,
    uint256[] memory signerPKs,
    Ballot.VoteType support
  ) internal view returns (SignatureConsumer.Signature[] memory sigs) {
    sigs = new SignatureConsumer.Signature[](signerPKs.length);
    bytes32 domain = getBridgeManagerDomain();
    for (uint256 i; i < signerPKs.length; i++) {
      bytes32 digest = domain.toTypedDataHash(Ballot.hash(proposalHash, support));
      sigs[i] = sign(signerPKs[i], digest);
    }
  }

  function resolveRoninTarget(GlobalProposal.TargetOption targetOption) internal view returns (address) {
    TNetwork network = config.getCurrentNetwork();
    if (!(network == DefaultNetwork.RoninMainnet.key() || network == DefaultNetwork.RoninTestnet.key())) {
      network = config.getCompanionNetwork(network);
    }

    if (targetOption == GlobalProposal.TargetOption.BridgeManager) {
      return config.getAddress(network, Contract.RoninBridgeManager.key());
    }
    if (targetOption == GlobalProposal.TargetOption.GatewayContract) {
      return config.getAddress(network, Contract.RoninGatewayV3.key());
    }
    if (targetOption == GlobalProposal.TargetOption.BridgeReward) {
      return config.getAddress(network, Contract.BridgeReward.key());
    }
    if (targetOption == GlobalProposal.TargetOption.BridgeSlash) {
      return config.getAddress(network, Contract.BridgeSlash.key());
    }
    if (targetOption == GlobalProposal.TargetOption.BridgeTracking) {
      return config.getAddress(network, Contract.BridgeTracking.key());
    }

    return address(0);
  }

  function resolveMainchainTarget(GlobalProposal.TargetOption targetOption) internal view returns (address) {
    TNetwork network = config.getCurrentNetwork();
    if (!(network == Network.EthMainnet.key() || network == Network.Goerli.key())) {
      network = config.getCompanionNetwork(network);
    }

    if (targetOption == GlobalProposal.TargetOption.BridgeManager) {
      return config.getAddress(network, Contract.MainchainBridgeManager.key());
    }
    if (targetOption == GlobalProposal.TargetOption.GatewayContract) {
      return config.getAddress(network, Contract.MainchainGatewayV3.key());
    }

    return address(0);
  }

  function sign(uint256 pk, bytes32 digest) private pure returns (SignatureConsumer.Signature memory sig) {
    (uint8 v, bytes32 r, bytes32 s) = vm.sign(pk, digest);
    sig.v = v;
    sig.r = r;
    sig.s = s;
  }
}
