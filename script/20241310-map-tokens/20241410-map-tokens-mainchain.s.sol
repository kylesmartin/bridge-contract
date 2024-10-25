// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import { Vm } from "forge-std/Vm.sol";

import { IBridgeManager } from "@ronin/contracts/interfaces/bridge/IBridgeManager.sol";
import { Proposal } from "@ronin/contracts/libraries/Proposal.sol";
import { Ballot } from "@ronin/contracts/libraries/Ballot.sol";

import { LibProxy } from "@fdk/libraries/LibProxy.sol";
import { TNetwork } from "script/utils/Network.sol";

import { MapTokenConfig } from "script/20241310-map-tokens/MapTokenConfig.s.sol";
import { LibProposal } from "script/shared/libraries/LibProposal.sol";
import { LibCompanionNetwork } from "script/shared/libraries/LibCompanionNetwork.sol";
import { Contract } from "script/utils/Contract.sol";
import { Network } from "script/utils/Network.sol";
import { IRoninBridgeManager } from "script/interfaces/IRoninBridgeManager.sol";
import { IMainchainBridgeManager } from "script/interfaces/IMainchainBridgeManager.sol";
import { ITransparentUpgradeableProxyV2 } from "script/interfaces/ITransparentUpgradeableProxyV2.sol";

contract Migration__20241410_MapTokens_Mainchain is MapTokenConfig {
  using LibCompanionNetwork for *;
  using LibProxy for *;

  address internal constant _SM_GOVERNOR = 0xe880802580a1fbdeF67ACe39D1B21c5b2C74f059;
  address internal constant _EXECUTOR = _SM_GOVERNOR;

  address[] internal mockGvs;
  address[] internal mockOps;

  Proposal.ProposalDetail internal _proposal;
  IRoninBridgeManager internal _ronBM;
  IMainchainBridgeManager internal _ethBM;

  function run() public virtual override {
    super.run();

    _ronBM = IRoninBridgeManager(loadContract(Contract.RoninBridgeManager.key()));
    uint256 expiry = block.timestamp + _DEFAULT_EXPIRY_DURATION;
    (address[] memory targets, uint256[] memory values, bytes[] memory callDatas, uint256[] memory gasAmounts) = getMainchainMapData();

    TNetwork companionNetwork = config.getCompanionNetwork(network());
    uint256 companionChainId = LibCompanionNetwork.companionChainId();

    _ethBM = IMainchainBridgeManager(config.getAddress(companionNetwork, Contract.MainchainBridgeManager.key()));
    LibProposal.verifyMainchainProposalGasAmount(companionNetwork, address(_ethBM), targets, values, callDatas, gasAmounts);

    vm.broadcast(_SM_GOVERNOR);
    vm.recordLogs();
    _ronBM.propose(companionChainId, expiry, _EXECUTOR, targets, values, callDatas, gasAmounts);
    Vm.Log[] memory recordedLogs = vm.getRecordedLogs();
    for (uint256 i; i < recordedLogs.length; ++i) {
      if (recordedLogs[i].emitter == address(_ronBM) && recordedLogs[i].topics[0] == IRoninBridgeManager.ProposalCreated.selector) {
        (_proposal,) = abi.decode(recordedLogs[i].data, (Proposal.ProposalDetail, address));
        break;
      }
    }
  }

  function _postCheck() internal virtual override {
    uint256 ronSnapshotId = vm.snapshot();
    genMockBOs(address(_ronBM));
    overrideMockBOs(address(_ronBM));

    Signature[] memory sigs = LibProposal.voteForBySignature(_ronBM, _proposal, Ballot.VoteType.For);

    (TNetwork prvNetwork, uint256 prvForkId) = switchTo(config.getCompanionNetwork(network()));

    uint256 ethSnapshotId = vm.snapshot();

    overrideMockBOs(address(_ethBM));

    // Cheat re-add executor as bridge operator since we assigned executor as bridge operator in the proposal
    address[] memory ops = new address[](1);
    ops[0] = makeAddr("cheat-re-added-sm-bo");
    uint96[] memory vws = new uint96[](1);
    vws[0] = 1;
    address[] memory gvs = new address[](1);
    gvs[0] = _SM_GOVERNOR;
    // SkyMavis Gnosis Safe
    vm.prank(0x51F6696Ae42C6C40CA9F5955EcA2aaaB1Cefb26e);
    ITransparentUpgradeableProxyV2(address(_ethBM)).functionDelegateCall(abi.encodeCall(IBridgeManager.addBridgeOperators, (vws, gvs, ops)));
    vm.prank(_SM_GOVERNOR);
    _ethBM.relayProposal(_proposal, new Ballot.VoteType[](sigs.length), sigs);

    vm.revertTo(ethSnapshotId);

    switchBack(prvNetwork, prvForkId);

    vm.revertTo(ronSnapshotId);

    // super._postCheck();
  }

  function genMockBOs(
    address bm
  ) internal {
    uint256 boCount = IBridgeManager(bm).totalBridgeOperator();

    delete mockGvs;
    delete mockOps;

    for (uint256 i; i < boCount; ++i) {
      (address gv, uint256 gvPK) = makeAddrAndKey(string.concat("mock-gv-", vm.toString(vm.unixTime()), "-", vm.toString(i)));
      (address op, uint256 opPK) = makeAddrAndKey(string.concat("mock-op-", vm.toString(vm.unixTime()), "-", vm.toString(i)));

      vm.rememberKey(gvPK);
      vm.rememberKey(opPK);

      mockGvs.push(gv);
      mockOps.push(op);
    }
  }

  function overrideMockBOs(
    address bm
  ) internal {
    uint256 boCount = IBridgeManager(bm).totalBridgeOperator();
    address[] memory bos = IBridgeManager(bm).getBridgeOperators();
    address pa = bm.getProxyAdmin();
    uint96[] memory vws = new uint96[](boCount);

    for (uint256 i; i < boCount; ++i) {
      vws[i] = IBridgeManager(bm).getBridgeOperatorWeight(bos[i]);
      require(vws[i] > 0, "BridgeOperator weight should be greater than 0");
    }

    vm.prank(pa);
    ITransparentUpgradeableProxyV2(bm).functionDelegateCall(abi.encodeCall(IBridgeManager.addBridgeOperators, (vws, mockGvs, mockOps)));

    // remove real bridge operators
    vm.prank(pa);
    ITransparentUpgradeableProxyV2(bm).functionDelegateCall(abi.encodeCall(IBridgeManager.removeBridgeOperators, (bos)));
  }
}
