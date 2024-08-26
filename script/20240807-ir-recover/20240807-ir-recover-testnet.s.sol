// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import { Vm } from "forge-std/Vm.sol";
import { console } from "forge-std/console.sol";
import { cheatBroadcast } from "@fdk/utils/Helpers.sol";
import { DefaultNetwork } from "@fdk/utils/DefaultNetwork.sol";
import { TNetwork } from "@fdk/types/Types.sol";
import { LibCompanionNetwork } from "script/shared/libraries/LibCompanionNetwork.sol";

import { Contract } from "../utils/Contract.sol";
import { Network } from "../utils/Network.sol";
import { Migration } from "../Migration.s.sol";
import { LibProposal } from "../shared/libraries/LibProposal.sol";
import { LibStorage } from "../shared/libraries/LibStorage.sol";

import { TransparentUpgradeableProxyV2, TransparentUpgradeableProxy } from "@ronin/contracts/extensions/TransparentUpgradeableProxyV2.sol";
import { IMainchainBridgeManager } from "script/interfaces/IMainchainBridgeManager.sol";
import { IRoninBridgeManager } from "script/interfaces/IRoninBridgeManager.sol";
import { MainchainBridgeManager } from "@ronin/contracts/mainchain/MainchainBridgeManager.sol";
import { IMainchainGatewayV3 } from "@ronin/contracts/interfaces/IMainchainGatewayV3.sol";
import { MainchainGatewayV3 } from "@ronin/contracts/mainchain/MainchainGatewayV3.sol";
import { IBridgeManagerCallback } from "@ronin/contracts/interfaces/bridge/IBridgeManagerCallback.sol";

import { Ballot } from "@ronin/contracts/libraries/Ballot.sol";
import { Proposal } from "@ronin/contracts/libraries/Proposal.sol";
import { Transfer } from "@ronin/contracts/libraries/Transfer.sol";
import { TokenStandard } from "@ronin/contracts/libraries/LibTokenInfo.sol";
import { SignatureConsumer } from "@ronin/contracts/interfaces/consumers/SignatureConsumer.sol";
import { LibProxy } from "@fdk/libraries/LibProxy.sol";

contract Migration__20240807_IR_Recover_Testnet is Migration {
  using LibProxy for *;
  using LibProposal for *;
  using LibCompanionNetwork for TNetwork;

  TNetwork _companionNetwork;
  TNetwork _currNetwork;
  uint256 _prevForkId;

  address private constant SM_GOVERNOR = address(0xd24D87DDc1917165435b306aAC68D99e0F49A3Fa);
  address private _multisigEth = 0x51F6696Ae42C6C40CA9F5955EcA2aaaB1Cefb26e;
  IMainchainBridgeManager private _mainchainBM;
  TransparentUpgradeableProxyV2 private _mainchainBMproxy;
  IMainchainGatewayV3 private _mainchainGW;
  IRoninBridgeManager private _roninBM;

  // address _prevBMLogic;`
  // address _newBMLogic;
  address _newGWLogic;

  Proposal.ProposalDetail private _proposal;

  function run() public virtual onlyOn(DefaultNetwork.RoninTestnet.key()) {
    _roninBM = IRoninBridgeManager(loadContract(Contract.RoninBridgeManager.key()));

    _currNetwork = network();
    (, _companionNetwork) = _currNetwork.companionNetworkData();
    (TNetwork prevNetwork, uint256 prevForkId) = switchTo(_companionNetwork);

    _mainchainBM = IMainchainBridgeManager(loadContract(Contract.MainchainBridgeManager.key()));
    _mainchainBMproxy = TransparentUpgradeableProxyV2(payable(address(_mainchainBM)));
    _mainchainGW = IMainchainGatewayV3(loadContract(Contract.MainchainGatewayV3.key()));

    _newGWLogic = _deployLogic(Contract.MainchainGatewayV3.key());
    uint256 snapshotId = vm.snapshot();
    {
      // _preCheck_Withdrawable();
      _perform_PrankFix();
      _perform_checkAfterPrankFix();
    }
    // Cheat to cache proposal
    Proposal.ProposalDetail memory _cache = _proposal;
    vm.revertTo(snapshotId);

    _proposal = _cache;

    switchBack(prevNetwork, prevForkId);

    _performCreateAndExecuteProposalOnRonin();

    (prevNetwork, prevForkId) = switchTo(_companionNetwork);

    _performRelayProposalOnMainchain();

    switchBack(prevNetwork, prevForkId);
  }

  function _performRelayProposalOnMainchain() internal {
    address[] memory gvs = _mainchainBM.getGovernors();
    Signature[] memory signatures = _proposal.generateSignatures(gvs, Ballot.VoteType.For);
    Ballot.VoteType[] memory _supports = new Ballot.VoteType[](signatures.length);

    vm.broadcast(SM_GOVERNOR);
    IMainchainBridgeManager(_mainchainBM).relayProposal(_proposal, _supports, signatures);
  }

  function _perform_PrankFix() internal {
    // vm.prank(_multisigEth);
    // _prevBMLogic = _mainchainBMproxy.implementation();
    // _newBMLogic = _deployLogic(Contract.MainchainBridgeManager.key());

    _recover_relayProposalWithCheatGovernors();

    // // 1. Upgrade to new version and call hotfix
    // cheatBroadcast(
    //   _multisigEth,
    //   address(_mainchainBMproxy),
    //   0,
    //   abi.encodeCall(
    //     TransparentUpgradeableProxy.upgradeToAndCall,
    //     (
    //       _newBMLogic,
    //       abi.encodeWithSelector(MainchainBridgeManager.hotfix__ir_recover.selector)
    //     )
    //   )
    // );

    // // 2. Downgrade to previous version
    // cheatBroadcast({
    //   from: _multisigEth,
    //   to: address(_mainchainBMproxy),
    //   callValue: 0,
    //   callData: abi.encodeWithSignature(
    //     "upgradeTo(address)",
    //     _prevBMLogic
    //   )
    // });
  }

  function _performCreateAndExecuteProposalOnRonin() internal {
    while (_roninBM.round(11155111) <= 7) {
      uint256 nonce = _roninBM.round(11155111) + 1;

      address[] memory gvs = _roninBM.getGovernors();
      address gv = gvs[0];

      vm.broadcast(gv);
      vm.recordLogs();
      _roninBM.propose({
        chainId: _proposal.chainId,
        expiryTimestamp: _proposal.expiryTimestamp,
        executor: _proposal.executor,
        targets: _proposal.targets,
        values: _proposal.values,
        calldatas: _proposal.calldatas,
        gasAmounts: _proposal.gasAmounts
      });

      Vm.Log[] memory logs = vm.getRecordedLogs();

      for (uint256 i = 0; i < logs.length; i++) {
        if (logs[i].emitter == address(_roninBM) && logs[i].topics[0] == IRoninBridgeManager.ProposalCreated.selector) {
          (_proposal,) = abi.decode(logs[i].data, (Proposal.ProposalDetail, address));
          break;
        }
      }

      console.log("Proposal nonce: ", _proposal.nonce);
      require(_proposal.nonce == nonce, "Invalid proposal nonce");

      LibProposal.voteForBySignature(_roninBM, _proposal, Ballot.VoteType.For);
    }
  }

  function _recover_relayProposalWithCheatGovernors() internal {
    // Create proposal
    _proposal = __recover_createProposal();

    // Validate proposal's gas amount
    LibProposal.verifyProposalGasAmount(address(_mainchainBM), _proposal.targets, _proposal.values, _proposal.calldatas, _proposal.gasAmounts);

    // Validate proposal's execution
    LibProposal.verifyProposalExecutionMainchain({ bm: address(_mainchainBM), proposal: _proposal, shouldRevertState: false });
  }

  function __recover_createProposal() internal view returns (Proposal.ProposalDetail memory proposal) {
    // struct ProposalDetail {
    //   // Nonce to make sure proposals are executed in order
    //   uint256 nonce;
    //   // Value 0: all chain should run this proposal
    //   // Other values: only specific chain has to execute
    //   uint256 chainId;
    //   uint256 expiryTimestamp;
    //   // The address that execute the proposal after the proposal passes.
    //   // Leave this address as address(0) to auto-execute by the last valid vote.
    //   address executor;
    //   address[] targets;
    //   uint256[] values;
    //   bytes[] calldatas;
    //   uint256[] gasAmounts;
    // }

    proposal.nonce = 8;
    proposal.chainId = 11155111;
    proposal.expiryTimestamp = block.timestamp + 12 days;
    proposal.executor = SM_GOVERNOR;

    // proposal.targets = new address[](2);
    // proposal.values = new uint256[](2);
    // proposal.calldatas = new bytes[](2);
    // proposal.gasAmounts = new uint256[](2);

    // proposal.targets[0] = address(_mainchainBM);
    // proposal.values[0] = 0;
    // proposal.calldatas[0] = abi.encodeCall(
    //     TransparentUpgradeableProxy.upgradeToAndCall,
    //     (
    //       _newBMLogic,
    //       abi.encodeWithSelector(MainchainBridgeManager.hotfix__ir_recover.selector)
    //     )
    //   );
    // proposal.gasAmounts[0] = 4000000;

    // proposal.targets[1] = address(_mainchainBM);
    // proposal.values[1] = 0;
    // proposal.calldatas[1] = abi.encodeWithSignature("upgradeTo(address)", _prevBMLogic);
    // proposal.gasAmounts[1] = 1000000;
    (, address[] memory operators, uint96[] memory weights) = _mainchainBM.getFullBridgeOperatorInfos();
    bool[] memory addeds = new bool[](operators.length);
    for (uint256 i = 0; i < operators.length; i++) {
      addeds[i] = true;
    }

    proposal.targets = new address[](2);
    proposal.values = new uint256[](2);
    proposal.calldatas = new bytes[](2);
    proposal.gasAmounts = new uint256[](2);

    proposal.targets[0] = address(_mainchainGW);
    proposal.values[0] = 0;
    proposal.gasAmounts[0] = 2000000;
    proposal.calldatas[0] = abi.encodeWithSignature(
      "functionDelegateCall(bytes)", abi.encodeWithSelector(IBridgeManagerCallback.onBridgeOperatorsAdded.selector, operators, weights, addeds)
    );

    proposal.targets[1] = address(_mainchainGW);
    proposal.values[1] = 0;
    proposal.calldatas[1] = abi.encodeWithSignature("upgradeTo(address)", _newGWLogic);
    proposal.gasAmounts[1] = 1000000;
  }

  function _preCheck_Withdrawable() internal {
    uint256 snapshotId = vm.snapshot();

    _fake_unpause();

    Transfer.Receipt memory dummyReceipt = _generateReceipt();

    SignatureConsumer.Signature[] memory sigs = new SignatureConsumer.Signature[](1);
    sigs[0].v = 28;
    sigs[0].r = 0xb377fd3c624426b0ef33f110dfc9424e6444f9000e8d4a859cd9102e59834544;
    sigs[0].s = 0x2e7f1f124b131944db2982c70f5ffc4054326facbbca95f161f3f042b58f52f8;

    vm.expectEmit(true, false, false, false, address(_mainchainGW));
    emit IMainchainGatewayV3.Withdrew(bytes32(0), dummyReceipt);
    _mainchainGW.submitWithdrawal(dummyReceipt, sigs);

    bool reverted = vm.revertTo(snapshotId);
    require(reverted, string.concat("Cannot revert to snapshot id: ", vm.toString(snapshotId)));
  }

  function _fake_unpause() internal { }

  function _perform_checkAfterPrankFix() internal {
    // - Total weight in `BM` and `GW` the same
    {
      uint256 totalWeightBM = _mainchainBM.getTotalWeight();
      uint96 totalWeightGW = getGWTotalWeight();
      require(totalWeightBM == uint256(totalWeightGW), "Mismatched total weight");
    }

    // - Weight of all operators in `BM` and `GW` the same
    (, address[] memory operatorsBM, uint96[] memory weightsBM) = _mainchainBM.getFullBridgeOperatorInfos();
    for (uint256 i = 0; i < operatorsBM.length; i++) {
      require(getGWWeight(operatorsBM[i]) == weightsBM[i], "Mismatched weight");
    }

    {
      _postCheck_Withdrawable();
    }

    // Check `WETHUnwrapper` is removed
    {
      // Method get removed, so it reverted in fallback with invalid deposit
      vm.expectRevert(abi.encodeWithSignature("ErrInvalidInfo()"));
      address(_mainchainGW).staticcall(abi.encodeWithSignature("WETHUnwrapper()"));
    }
  }

  function _postCheck_Withdrawable() internal {
    uint256 snapshotId = vm.snapshot();
    _fake_unpause();

    Transfer.Receipt memory dummyReceipt = _generateReceipt();

    SignatureConsumer.Signature[] memory sigs = new SignatureConsumer.Signature[](1);
    sigs[0].v = 28;
    sigs[0].r = 0xb377fd3c624426b0ef33f110dfc9424e6444f9000e8d4a859cd9102e59834544;
    sigs[0].s = 0x2e7f1f124b131944db2982c70f5ffc4054326facbbca95f161f3f042b58f52f8;

    vm.expectRevert(abi.encodeWithSelector(IMainchainGatewayV3.ErrInvalidSigner.selector, 0xDf6d11d428FEdd8f3a5d800fBDe66Bf6dD070577, 0, sigs[0]));
    _mainchainGW.submitWithdrawal(dummyReceipt, sigs);

    bool reverted = vm.revertTo(snapshotId);
    require(reverted, string.concat("Cannot revert to snapshot id: ", vm.toString(snapshotId)));
  }

  function _postCheck() internal virtual override {
    // switchTo(_companionNetwork);

    // Cheat to unpause of MainchainGatewayV3 to self to pass post-check.
    // _fake_unpause();

    // Cheat to change admin of MainchainBridgeManager to self to pass post-check.
    // vm.prank(_multisigEth);
    // TransparentUpgradeableProxy(payable(address(_mainchainBM))).changeAdmin(address(_mainchainBM));

    // switchTo(DefaultNetwork.RoninTestnet.key());

    // Cheat to change admin of RoninBridgeManager to self to pass post-check.
    address payable roninBM = loadContract(Contract.RoninBridgeManager.key());
    address admin = roninBM.getProxyAdmin();
    vm.prank(admin);
    TransparentUpgradeableProxy(roninBM).changeAdmin(roninBM);

    super._postCheck();
  }

  function getGWTotalWeight() public view returns (uint96 totalWeight) {
    uint256 $$_operatorWeightSlot = 125;
    bytes32 paddedTotalWeight = vm.load(address(_mainchainGW), bytes32($$_operatorWeightSlot));
    totalWeight = uint96(uint256(paddedTotalWeight));
    console.log(string.concat("[STORAGE] Total weight in GW is ", vm.toString(totalWeight)));
  }

  function getGWWeight(address operator) public view returns (uint96 weight) {
    uint256 $$_operatorWeightSlot = 126;
    bytes32 $$ = LibStorage.getMappingElementSlotIndex(operator, $$_operatorWeightSlot);
    bytes32 paddedWeight = vm.load(address(_mainchainGW), $$);
    weight = uint96(uint256(paddedWeight));
    console.log(string.concat("[STORAGE] Weight of ", vm.toString(operator), " is ", vm.toString(weight)));
  }

  function _generateReceipt() internal returns (Transfer.Receipt memory receipt_) {
    // struct Receipt {
    //   uint256 id;
    //   Kind kind;
    //   TokenOwner mainchain;
    //   TokenOwner ronin;
    //   TokenInfo info;
    // }

    // struct TokenOwner {
    //   address addr;
    //   address tokenAddr;
    //   uint256 chainId;
    // }

    /* Receipt({
        id: 166631 [1.666e5],
        kind: 1,
        mainchain: TokenOwner({
            addr: 0x4Ab12E7CE31857Ee022f273e8580F73335a73c0B,
            tokenAddr: 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2,
            chainId: 1
        }),
        ronin: TokenOwner({
            addr: 0x03E1f309d281b0af1A17EBb29e89136c05b67206,
            tokenAddr: 0xc99a6A985eD2Cac1ef41640596C5A5f9F4E19Ef5,
            chainId: 2021
        }),
        info: TokenInfo({
            erc: 0,
            id: 0,
            quantity: 3996093750000000000000 [3.996e21]
        })
    }) */

    address mainchainETH = 0x1Aa1BC6BaEFCF09D6Fd0139B828b5E764D050F08;
    address roninETH = 0x29C6F8349A028E1bdfC68BFa08BDee7bC5D47E16;

    receipt_.id = 2021;
    receipt_.kind = Transfer.Kind.Withdrawal;
    receipt_.mainchain.addr = makeAddr("recipient-mainchain");
    receipt_.mainchain.tokenAddr = mainchainETH;
    receipt_.mainchain.chainId = 11155111;
    receipt_.ronin.addr = makeAddr("recipient-ronin");
    receipt_.ronin.tokenAddr = roninETH;
    receipt_.ronin.chainId = 2021;
    receipt_.info.erc = TokenStandard.ERC20;
    receipt_.info.id = 0;
    receipt_.info.quantity = 3996093750000000000000;
  }
}
