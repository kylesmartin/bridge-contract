// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import { IBridgeManager } from "@ronin/contracts/interfaces/bridge/IBridgeManager.sol";
import { Proposal } from "src/libraries/Proposal.sol";
import { Ballot } from "src/libraries/Ballot.sol";

import { Vm } from "forge-std/Vm.sol";

import { LibProxy } from "@fdk/libraries/LibProxy.sol";
import { TNetwork } from "@fdk/types/TNetwork.sol";

import { Migrate_Assets_Base } from "script/20241217-migrate-assets/Migrate_Assets_Base.s.sol";

import { ITransparentUpgradeableProxyV2 } from "script/interfaces/ITransparentUpgradeableProxyV2.sol";
import { IRoninBridgeManager } from "script/interfaces/IRoninBridgeManager.sol";
import { IMainchainBridgeManager } from "script/interfaces/IMainchainBridgeManager.sol";

import { LibCompanionNetwork } from "script/shared/libraries/LibCompanionNetwork.sol";
import { LibProposal } from "script/shared/libraries/LibProposal.sol";
import { Contract } from "script/utils/Contract.sol";

contract Migration_02_Propose_Upgrades is Migrate_Assets_Base {
  using LibCompanionNetwork for *;
  using LibProxy for *;

  uint256 internal constant _DEFAULT_EXPIRY_DURATION = 14 days;

  uint256 internal _companionChainId;
  TNetwork internal _companionNetwork;
  Proposal.ProposalDetail internal _ronProposal;
  Proposal.ProposalDetail internal _ethProposal;
  uint256 internal _expiry;

  address[] internal mockGvs;
  address[] internal mockOps;

  IRoninBridgeManager internal _ronBM;
  IMainchainBridgeManager internal _ethBM;

  function _getProposalExecutor() internal view virtual override returns (address) {
    return address(0);
  }

  function _getProposalProposer() internal view virtual override returns (address) {
    return _ronBM.getGovernors()[0];
  }

  function _getRoninMigratorAddress() internal view virtual override returns (address) {
    revert("Not implemented");
  }

  function _getEthereumMigratorAddress() internal view virtual override returns (address) {
    revert("Not implemented");
  }

  function _getRoninGatewayV3Logic() internal view virtual override returns (address) {
    revert("Not implemented");
  }

  function _getMainchainGatewayV3Logic() internal view virtual override returns (address) {
    revert("Not implemented");
  }

  function _getRoninPauseEnforcer() internal view virtual override returns (address) {
    revert("Not implemented");
  }

  function _getEthereumPauseEnforcer() internal view virtual override returns (address) {
    revert("Not implemented");
  }

  function run() public virtual {
    (_companionChainId, _companionNetwork) = network().companionNetworkData();

    _expiry = block.timestamp + _DEFAULT_EXPIRY_DURATION;
    _ronBM = IRoninBridgeManager(loadContract(Contract.RoninBridgeManager.key()));
    _ethBM = IMainchainBridgeManager(vme.getAddress(_companionNetwork, Contract.MainchainBridgeManager.key()));

    _propose_upgradeAndRestrictERC20_RoninGatewayV3();
    _propose_upgradeAndRestrictERC20_MainchainGatewayV3();
  }

  function _propose_upgradeAndRestrictERC20_MainchainGatewayV3() internal {
    address[] memory targets = new address[](1);
    bytes[] memory callDatas = new bytes[](1);
    uint256[] memory values = new uint256[](1);
    uint256[] memory gasAmounts = new uint256[](1);

    targets[0] = vme.getAddress(_companionNetwork, Contract.MainchainGatewayV3.key());
    callDatas[0] = abi.encodeCall(
      ITransparentUpgradeableProxyV2.upgradeToAndCall,
      (_getMainchainGatewayV3Logic(), abi.encodeWithSignature("initializeV5(address,address)", _getEthereumMigratorAddress(), _getEthereumPauseEnforcer()))
    );
    values[0] = 0;
    gasAmounts[0] = 1_000_000;

    LibProposal.verifyMainchainProposalGasAmount(_companionNetwork, address(_ethBM), targets, values, callDatas, gasAmounts);

    vm.broadcast(_getProposalProposer());
    vm.recordLogs();
    _ronBM.propose(_companionChainId, _expiry, _getProposalExecutor(), targets, values, callDatas, gasAmounts);
    Vm.Log[] memory recordedLogs = vm.getRecordedLogs();
    for (uint256 i; i < recordedLogs.length; ++i) {
      if (recordedLogs[i].emitter == address(_ronBM) && recordedLogs[i].topics[0] == IRoninBridgeManager.ProposalCreated.selector) {
        (_ethProposal,) = abi.decode(recordedLogs[i].data, (Proposal.ProposalDetail, address));
        break;
      }
    }
  }

  function _propose_upgradeAndRestrictERC20_RoninGatewayV3() internal {
    address gw = loadContract(Contract.RoninGatewayV3.key());

    address[] memory targets = new address[](1);
    bytes[] memory callDatas = new bytes[](1);
    uint256[] memory values = new uint256[](1);
    uint256[] memory gasAmounts = new uint256[](1);

    targets[0] = gw;
    callDatas[0] = abi.encodeCall(
      ITransparentUpgradeableProxyV2.upgradeToAndCall,
      (
        _getRoninGatewayV3Logic(),
        abi.encodeWithSignature(
          "initializeV4(address,address,address)", loadContract(Contract.WRON.key()), _getRoninMigratorAddress(), _getRoninPauseEnforcer()
        )
      )
    );
    values[0] = 0;
    gasAmounts[0] = 1_000_000;

    uint256 nonce = _ronBM.round(block.chainid) + 1;
    _ronProposal = LibProposal.createProposal(address(_ronBM), nonce, _expiry, targets, values, callDatas, gasAmounts);
    _ronProposal.executor = _getProposalExecutor();

    vm.broadcast(_getProposalProposer());
    _ronBM.propose(block.chainid, _expiry, _getProposalExecutor(), targets, values, callDatas, gasAmounts);
  }

  function _postCheck() internal virtual override {
    // Simulate voting for the Ronin proposal
    LibProposal.voteFor(_ronBM, _ronProposal);

    // Simulate voting for the Ethereum proposal
    uint256 ronSnapshotId = vm.snapshot();
    genMockBOs(address(_ronBM));
    overrideMockBOs(address(_ronBM));

    Signature[] memory sigs = LibProposal.voteForBySignature(_ronBM, _ethProposal, Ballot.VoteType.For);

    (TNetwork prvNetwork, uint256 prvForkId) = switchTo(_companionNetwork);

    uint256 ethSnapshotId = vm.snapshot();

    overrideMockBOs(address(_ethBM));

    // Cheat re-add executor as bridge operator since we assigned executor as bridge operator in the proposal
    address[] memory ops = new address[](1);
    ops[0] = makeAddr("cheat-re-added-sm-bo");
    uint96[] memory vws = new uint96[](1);
    vws[0] = 1;
    address[] memory gvs = new address[](1);
    gvs[0] = _getProposalExecutor();
    // SkyMavis Gnosis Safe
    vm.prank(0x51F6696Ae42C6C40CA9F5955EcA2aaaB1Cefb26e);
    ITransparentUpgradeableProxyV2(address(_ethBM)).functionDelegateCall(abi.encodeCall(IBridgeManager.addBridgeOperators, (vws, gvs, ops)));
    vm.prank(_getProposalExecutor());
    _ethBM.relayProposal(_ethProposal, new Ballot.VoteType[](sigs.length), sigs);

    vm.revertTo(ethSnapshotId);

    switchBack(prvNetwork, prvForkId);

    vm.revertTo(ronSnapshotId);
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
