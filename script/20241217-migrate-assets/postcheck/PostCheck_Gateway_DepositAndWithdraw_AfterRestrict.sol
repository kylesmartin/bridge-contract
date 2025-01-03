// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import { console } from "forge-std/console.sol";
import { Vm } from "forge-std/Vm.sol";
import { BasePostCheck } from "script/post-check/BasePostCheck.s.sol";
import { MockERC20 } from "src/mocks/token/MockERC20.sol";
import { MockERC721 } from "src/mocks/token/MockERC721.sol";
import { Contract } from "script/utils/Contract.sol";
import { TokenStandard } from "src/libraries/LibTokenInfo.sol";
import { Transfer as LibTransfer } from "src/libraries/Transfer.sol";
import { TNetwork } from "@fdk/types/TNetwork.sol";
import { DefaultNetwork } from "@fdk/utils/DefaultNetwork.sol";
import { LibProxy } from "@fdk/libraries/LibProxy.sol";
import { LibCompanionNetwork } from "script/shared/libraries/LibCompanionNetwork.sol";
import { IBridgeManager } from "src/interfaces/bridge/IBridgeManager.sol";
import { LibArray } from "script/shared/libraries/LibArray.sol";
import { IRoninGatewayV3 } from "src/interfaces/IRoninGatewayV3.sol";
import { IRoninBridgeManager } from "script/interfaces/IRoninBridgeManager.sol";
import { IMainchainBridgeManager } from "script/interfaces/IMainchainBridgeManager.sol";
import { IWETH } from "src/interfaces/IWETH.sol";
import { IMainchainGatewayV3 } from "src/interfaces/IMainchainGatewayV3.sol";
import { IQuorum } from "src/interfaces/IQuorum.sol";
import { ITransparentUpgradeableProxyV2 } from "script/interfaces/ITransparentUpgradeableProxyV2.sol";
import { IHasContracts } from "src/interfaces/collections/IHasContracts.sol";
import { ContractType } from "src/utils/ContractType.sol";
import { FunctionRestrictable } from "src/extensions/FunctionRestrictable.sol";

abstract contract PostCheck_Gateway_DepositAndWithdraw_AfterRestrict is BasePostCheck {
  using LibProxy for *;
  using LibArray for *;
  using LibCompanionNetwork for *;
  using LibTransfer for LibTransfer.Request;
  using LibTransfer for LibTransfer.Receipt;

  address private user = makeAddr("user");
  uint256 private quantity;

  LibTransfer.Request depositReq;
  LibTransfer.Request withdrawReq;

  MockERC20 private ronERC20;
  MockERC721 private ronERC721;
  MockERC20 private ethERC20;
  MockERC721 private ethERC721;

  address[] private ronTokens = new address[](2);
  address[] private ethTokens = new address[](2);
  TokenStandard[] private standards = [TokenStandard.ERC20, TokenStandard.ERC721];

  uint256 private ronChainId;
  uint256 private ethChainId;

  IWETH private ethWETH;
  MockERC20 private ronWETH;

  TNetwork private currNetwork;
  TNetwork private companionNetwork;

  function _setUp() private onlyOnRoninNetworkOrLocal {
    console.log("RoninBridgeManager", ronBM);
    console.log("MainchainBridgeManager", ethBM);

    console.log("RoninGateway", ronGW);
    console.log("MainchainGateway", ethGW);

    _setUpOnRonin();
    _setUpOnMainchain();
    _mapTokenRonin();
    _mapTokenMainchain();
  }

  function _mapTokenRonin() private {
    uint256[] memory chainIds = new uint256[](2);
    chainIds[0] = network().companionChainId();
    chainIds[1] = chainIds[0];

    address admin = ronGW.getProxyAdmin();
    console.log("Admin for ronin gateway", admin);

    vm.prank(admin);
    ITransparentUpgradeableProxyV2(ronGW).functionDelegateCall(abi.encodeCall(IRoninGatewayV3.mapTokens, (ronTokens, ethTokens, chainIds, standards)));
  }

  function _mapTokenMainchain() private {
    (, companionNetwork) = network().companionNetworkData();
    (TNetwork prevNetwork, uint256 prevForkId) = switchTo(companionNetwork);

    uint256[][4] memory thresholds;
    thresholds[0] = new uint256[](2);
    thresholds[0][0] = 200_000_000 ether;
    thresholds[1] = new uint256[](2);
    thresholds[1][0] = 800_000_000 ether;
    thresholds[2] = new uint256[](2);
    thresholds[2][0] = 10;
    thresholds[3] = new uint256[](2);
    thresholds[3][0] = 500_000_000 ether;

    console.log("Mainchain Gateway", ethGW);
    address admin = ethGW.getProxyAdmin();
    console.log("Admin", admin);

    vm.prank(admin);
    ITransparentUpgradeableProxyV2(ethGW).functionDelegateCall(
      abi.encodeCall(IMainchainGatewayV3.mapTokensAndThresholds, (ethTokens, ronTokens, standards, thresholds))
    );

    switchBack(prevNetwork, prevForkId);
  }

  function _setUpOnRonin() private {
    ronERC20 = new MockERC20("RoninERC20", "RERC20");
    ronERC721 = new MockERC721("RoninERC721", "RERC721");

    ronTokens[0] = address(ronERC20);
    ronTokens[1] = address(ronERC721);

    ronChainId = block.chainid;
    currNetwork = network();

    vm.deal(user, 10 ether);
    deal(address(ronERC20), user, 1000 ether);

    ronWETH = MockERC20(loadContract(Contract.WETH.key()));
  }

  function _setUpOnMainchain() private {
    (, companionNetwork) = network().companionNetworkData();
    (TNetwork prevNetwork, uint256 prevForkId) = switchTo(companionNetwork);

    ethChainId = block.chainid;
    gwDomainHash = IMainchainGatewayV3(ethGW).DOMAIN_SEPARATOR();

    ethERC20 = new MockERC20("MainchainERC20", "MERC20");
    ethERC721 = new MockERC721("MainchainERC721", "MERC721");

    ethTokens[0] = address(ethERC20);
    ethTokens[1] = address(ethERC721);

    ethWETH = IWETH(loadContract(Contract.WETH.key()));

    vm.deal(user, 10 ether);
    deal(address(ethERC20), user, 1000 ether);

    switchBack(prevNetwork, prevForkId);
  }

  function _validate_Gateway_DepositAndWithdraw() internal {
    _setUp();

    validate_Can_RequestWithdraw_ERC721_RoninGateway_And_CanWithdraw_In_MainchainGateway();
    validate_Can_RequestDeposit_ERC721_MainchainGateway_And_OperatorCanDeposit_In_RoninGateway();
    validate_RevertIf_Deposit_WETH_MainchainGateway_ButOperatorCanDeposit_In_RoninGateway();
    // validate_Gateway_RevertIf_OperatorsRenounced_InsufficientThreshold_Withdraw_ERC20();
    validate_RevertIf_RequestWithdraw_ETH_RoninGateway_But_CanWithdraw_In_MainchainGateway();
    validate_Gateway_WETHAddressUnchanged();
    // validate_Gateway_Deposit_ETH();
    // validate_Gateway_RevertIf_InsufficientSentValue_Deposit_ETH();

    // validate_Gateway_RevertIf_DuplicatedSigs_Withdraw_ERC20();
    // validate_Gateway_RevertIf_UnsortedSigs_Withdraw_ERC20();
    validate_HasBridgeManager();
    // validate_Gateway_Deposit_ERC20();
    // validate_Gateway_RevertIf_InsufficientThreshold_Deposit_ERC20();
    // validate_Gateway_Withdraw_ERC20();
    // validate_Gateway_RevertIf_InvalidSignature_Withdraw_ERC20();
    // validate_Gateway_RevertIf_InsufficientThreshold_Withdraw_ERC20();
  }

  function validate_Can_RequestDeposit_ERC721_MainchainGateway_And_OperatorCanDeposit_In_RoninGateway()
    private
    onPostCheck("validate_Can_RequestDeposit_ERC721_MainchainGateway_And_OperatorCanDeposit_In_RoninGateway")
    onlyOnRoninNetworkOrLocal
  {
    (TNetwork prevNetwork, uint256 prevForkId) = switchTo(companionNetwork);
    uint256 snapshotId = vm.snapshot();

    depositReq.recipientAddr = makeAddr("ronin-recipient");
    depositReq.tokenAddr = address(ethERC721);
    depositReq.info.erc = TokenStandard.ERC721;
    depositReq.info.id = 1;

    ethERC721.mint(user, depositReq.info.id);
    vm.prank(user);
    ethERC721.approve(ethGW, depositReq.info.id);

    vm.prank(user);
    vm.recordLogs();
    IMainchainGatewayV3(ethGW).requestDepositFor(depositReq);

    (LibTransfer.Receipt memory receipt,) = _getReceiptHash(ethGW, IMainchainGatewayV3.DepositRequested.selector);

    vm.revertTo(snapshotId);

    switchBack(prevNetwork, prevForkId);

    ronERC721.mint(address(ronGW), depositReq.info.id);

    overrideMockBOs(ronBM);

    uint256 minSigRequired = _calcMinSigOrVoteRequired(ronBM, ronGW);
    assertTrue(minSigRequired > 1, "Invalid test setup");

    for (uint256 i; i < minSigRequired; ++i) {
      vm.prank(mockOps[i]);
      IRoninGatewayV3(ronGW).depositFor(receipt);
    }
  }

  function validate_Can_RequestWithdraw_ERC721_RoninGateway_And_CanWithdraw_In_MainchainGateway()
    private
    onPostCheck("validate_Can_RequestWithdraw_ERC721_RoninGateway_And_CanWithdraw_In_MainchainGateway")
    onlyOnRoninNetworkOrLocal
  {
    withdrawReq.recipientAddr = makeAddr("mainchain-recipient");
    withdrawReq.tokenAddr = address(ronERC721);
    withdrawReq.info.erc = TokenStandard.ERC721;
    withdrawReq.info.id = 1;

    ronERC721.mint(user, withdrawReq.info.id);
    vm.prank(user);
    ronERC721.approve(ronGW, withdrawReq.info.id);
    vm.prank(user);
    IRoninGatewayV3(ronGW).requestWithdrawalFor(withdrawReq, ethChainId);

    (LibTransfer.Receipt memory receipt, bytes32 receiptHash) = _getReceiptHash(ronGW, IRoninGatewayV3.WithdrawalRequested.selector);

    (TNetwork prevNetwork, uint256 prevForkId) = switchTo(companionNetwork);
    uint256 snapshotId = vm.snapshot();

    bytes32 receiptDigest = LibTransfer.receiptDigest(gwDomainHash, receiptHash);

    overrideMockBOs(ethBM);

    uint256 minSigRequired = _calcMinSigOrVoteRequired(ethBM, ethGW);
    assertTrue(minSigRequired > 1, "Invalid test setup");

    Signature[] memory sigs = _bulkSignReceipt(mockOps.slice(0, minSigRequired), receiptDigest);
    ethERC721.mint(address(ethGW), withdrawReq.info.id);
    IMainchainGatewayV3(ethGW).submitWithdrawal(receipt, sigs);

    vm.revertTo(snapshotId);
    switchBack(prevNetwork, prevForkId);
  }

  function validate_RevertIf_RequestWithdraw_ETH_RoninGateway_But_CanWithdraw_In_MainchainGateway()
    private
    onPostCheck("validate_RevertIf_RequestWithdraw_ETH_RoninGateway_But_CanWithdraw_In_MainchainGateway")
    onlyOnRoninNetworkOrLocal
  {
    withdrawReq.recipientAddr = makeAddr("mainchain-recipient");
    withdrawReq.tokenAddr = address(ronWETH);
    withdrawReq.info.erc = TokenStandard.ERC20;
    withdrawReq.info.id = 0;
    withdrawReq.info.quantity = 1 ether;

    if (network() == DefaultNetwork.RoninTestnet.key()) {
      withdrawReq.info.quantity = 0.00009 ether; // Low tier 0.0001
    }

    deal(address(ronWETH), user, withdrawReq.info.quantity);
    vm.prank(user);
    ronWETH.approve(ronGW, withdrawReq.info.quantity);
    vm.prank(user);
    vm.expectRevert(abi.encodeWithSelector(FunctionRestrictable.ErrRestricted.selector, IRoninGatewayV3.requestWithdrawalFor.selector, TokenStandard.ERC20));
    IRoninGatewayV3(ronGW).requestWithdrawalFor(withdrawReq, ethChainId);

    // Un-restrict
    address admin = ronGW.getProxyAdmin();
    uint256 snapshotId = vm.snapshot();
    vm.prank(admin);
    ITransparentUpgradeableProxyV2(ronGW).functionDelegateCall(
      abi.encodeCall(FunctionRestrictable.restrict, (IRoninGatewayV3.requestWithdrawalFor.selector, 0))
    );

    vm.prank(user);
    IRoninGatewayV3(ronGW).requestWithdrawalFor(withdrawReq, ethChainId);
    (LibTransfer.Receipt memory receipt, bytes32 receiptHash) = _getReceiptHash(ronGW, IRoninGatewayV3.WithdrawalRequested.selector);

    (TNetwork prevNetwork, uint256 prevForkId) = switchTo(companionNetwork);
    uint256 ethSnapshotId = vm.snapshot();

    bytes32 receiptDigest = LibTransfer.receiptDigest(gwDomainHash, receiptHash);

    overrideMockBOs(ethBM);

    uint256 minSigRequired = _calcMinSigOrVoteRequired(ethBM, ethGW);
    assertTrue(minSigRequired > 1, "Invalid test setup");

    Signature[] memory sigs = _bulkSignReceipt(mockOps.slice(0, minSigRequired), receiptDigest);
    IMainchainGatewayV3(ethGW).submitWithdrawal(receipt, sigs);
    vm.revertTo(ethSnapshotId);

    switchBack(prevNetwork, prevForkId);
    vm.revertTo(snapshotId);
  }

  function validate_Gateway_RevertIf_OperatorsRenounced_InsufficientThreshold_Withdraw_ERC20()
    private
    onPostCheck("validate_Gateway_RevertIf_OperatorsRenounced_InsufficientThreshold_Withdraw_ERC20")
    onlyOnRoninNetworkOrLocal
  {
    withdrawReq.recipientAddr = makeAddr("mainchain-recipient");
    withdrawReq.tokenAddr = address(ronERC20);
    withdrawReq.info.erc = TokenStandard.ERC20;
    withdrawReq.info.id = 0;
    withdrawReq.info.quantity = 1 ether;

    vm.prank(user);
    ronERC20.approve(ronGW, withdrawReq.info.quantity);

    vm.prank(user);
    vm.recordLogs();
    IRoninGatewayV3(ronGW).requestWithdrawalFor(withdrawReq, ethChainId);

    (LibTransfer.Receipt memory receipt, bytes32 receiptHash) = _getReceiptHash(ronGW, IRoninGatewayV3.WithdrawalRequested.selector);

    (TNetwork prevNetwork, uint256 prevForkId) = switchTo(companionNetwork);
    uint256 snapshotId = vm.snapshot();

    bytes32 receiptDigest = LibTransfer.receiptDigest(gwDomainHash, receiptHash);

    overrideMockBOs(ethBM);

    uint256 minSigRequired = _calcMinSigOrVoteRequired(ethBM, ethGW);
    uint256 unmetSigCount = minSigRequired - 1;
    console.log("Unmet sig count", unmetSigCount);
    assertTrue(unmetSigCount >= 1, "Invalid test setup");

    // Sign first to get renounced operator signatures
    Signature[] memory sigs = _bulkSignReceipt(mockOps, receiptDigest);

    // Cache to be renounced operators
    address[] memory gvsToRemove = mockOps.slice(unmetSigCount, mockOps.length);

    uint256 reAddOpCount = mockOps.length - unmetSigCount;

    mockOps = mockOps.slice(0, unmetSigCount);
    mockGvs = mockGvs.slice(0, unmetSigCount);

    address[] memory newOps = new address[](reAddOpCount);
    address[] memory newGvs = new address[](reAddOpCount);
    uint96[] memory newVWs = new uint96[](reAddOpCount);

    for (uint256 i; i < reAddOpCount; ++i) {
      uint256 opPK;
      uint256 gvPK;

      (newOps[i], opPK) = makeAddrAndKey(string.concat("new-op", vm.toString(i)));
      (newGvs[i], gvPK) = makeAddrAndKey(string.concat("new-gv", vm.toString(i)));
      newVWs[i] = 100;

      mockOps.push(newOps[i]);
      mockGvs.push(newGvs[i]);

      vm.rememberKey(opPK);
      vm.rememberKey(gvPK);
    }

    // Re-add new operators
    vm.prank(address(ethBM));
    ITransparentUpgradeableProxyV2(ethBM).functionDelegateCall(abi.encodeCall(IBridgeManager.addBridgeOperators, (newVWs, newGvs, newOps)));

    // Renounce operators
    vm.prank(address(ethBM));
    ITransparentUpgradeableProxyV2(ethBM).functionDelegateCall(abi.encodeCall(IBridgeManager.removeBridgeOperators, (gvsToRemove)));

    assertEq(IMainchainBridgeManager(ethBM).totalBridgeOperator(), 4, "Invalid total BOs");

    vm.expectRevert();
    IMainchainGatewayV3(ethGW).submitWithdrawal(receipt, sigs);

    vm.revertTo(snapshotId);
    switchBack(prevNetwork, prevForkId);
  }

  function validate_Gateway_RevertIf_InsufficientSentValue_Deposit_ETH()
    private
    onPostCheck("validate_Gateway_RevertIf_InsufficientSentValue_Deposit_ETH")
    onlyOnRoninNetworkOrLocal
  {
    depositReq.recipientAddr = makeAddr("ronin-recipient");
    depositReq.tokenAddr = address(0x0);
    depositReq.info.erc = TokenStandard.ERC20;
    depositReq.info.id = 0;
    depositReq.info.quantity = 1 ether;

    (TNetwork prevNetwork, uint256 prevForkId) = switchTo(companionNetwork);
    uint256 snapshotId = vm.snapshot();

    vm.deal(user, depositReq.info.quantity);
    vm.prank(user);
    vm.expectRevert();
    IMainchainGatewayV3(ethGW).requestDepositFor{ value: depositReq.info.quantity - 1 }(depositReq);

    vm.revertTo(snapshotId);
    switchBack(prevNetwork, prevForkId);
  }

  function validate_RevertIf_Deposit_WETH_MainchainGateway_ButOperatorCanDeposit_In_RoninGateway()
    private
    onPostCheck("validate_RevertIf_Deposit_WETH_MainchainGateway_ButOperatorCanDeposit_In_RoninGateway")
    onlyOnRoninNetworkOrLocal
  {
    depositReq.recipientAddr = makeAddr("ronin-recipient");
    depositReq.tokenAddr = address(ethWETH);
    depositReq.info.erc = TokenStandard.ERC20;
    depositReq.info.id = 0;
    depositReq.info.quantity = 1 ether;

    (TNetwork prevNetwork, uint256 prevForkId) = switchTo(companionNetwork);
    uint256 snapshotId = vm.snapshot();

    deal(address(ethWETH), user, depositReq.info.quantity);

    vm.prank(user);
    ethWETH.approve(ethGW, depositReq.info.quantity);

    uint256 balBefore = ethGW.balance;

    vm.prank(user);
    vm.recordLogs();
    vm.expectRevert(abi.encodeWithSelector(FunctionRestrictable.ErrRestricted.selector, IMainchainGatewayV3.requestDepositFor.selector, TokenStandard.ERC20));
    IMainchainGatewayV3(ethGW).requestDepositFor(depositReq);

    // Un-restrict
    address admin = ethGW.getProxyAdmin();
    vm.prank(admin);
    ITransparentUpgradeableProxyV2(ethGW).functionDelegateCall(
      abi.encodeCall(FunctionRestrictable.restrict, (IMainchainGatewayV3.requestDepositFor.selector, 0))
    );

    vm.prank(user);
    vm.recordLogs();
    IMainchainGatewayV3(ethGW).requestDepositFor(depositReq);

    uint256 balAfter = address(ethGW).balance;
    assertEq(balAfter - balBefore, depositReq.info.quantity, "ETH should be deposited");

    (LibTransfer.Receipt memory receipt,) = _getReceiptHash(ethGW, IMainchainGatewayV3.DepositRequested.selector);

    vm.revertTo(snapshotId);
    switchBack(prevNetwork, prevForkId);

    overrideMockBOs(ronBM);

    uint256 minVoteRequired = _calcMinSigOrVoteRequired(ronBM, ronGW);
    assertTrue(minVoteRequired > 1, "Invalid test setup");

    for (uint256 i; i < minVoteRequired; ++i) {
      vm.prank(mockOps[i]);
      IRoninGatewayV3(ronGW).depositFor(receipt);
    }
  }

  function validate_Gateway_Deposit_ETH() private onPostCheck("validate_Gateway_Deposit_ETH") onlyOnRoninNetworkOrLocal {
    depositReq.recipientAddr = makeAddr("ronin-recipient");
    depositReq.tokenAddr = address(0x0);
    depositReq.info.erc = TokenStandard.ERC20;
    depositReq.info.id = 0;
    depositReq.info.quantity = 1 ether;

    (TNetwork prevNetwork, uint256 prevForkId) = switchTo(companionNetwork);
    uint256 snapshotId = vm.snapshot();

    vm.deal(user, depositReq.info.quantity);
    vm.prank(user);

    uint256 balBefore = address(ethGW).balance;

    vm.recordLogs();
    IMainchainGatewayV3(ethGW).requestDepositFor{ value: depositReq.info.quantity }(depositReq);

    uint256 balAfter = address(ethGW).balance;
    assertEq(balAfter - balBefore, depositReq.info.quantity, "ETH should be deposited");

    (LibTransfer.Receipt memory receipt,) = _getReceiptHash(ethGW, IMainchainGatewayV3.DepositRequested.selector);

    vm.revertTo(snapshotId);
    switchBack(prevNetwork, prevForkId);

    overrideMockBOs(ronBM);

    uint256 minVoteRequired = _calcMinSigOrVoteRequired(ronBM, ronGW);
    assertTrue(minVoteRequired > 1, "Invalid test setup");

    for (uint256 i; i < minVoteRequired; ++i) {
      vm.prank(mockOps[i]);
      IRoninGatewayV3(ronGW).depositFor(receipt);
    }
  }

  function validate_Gateway_WETHAddressUnchanged() private onPostCheck("validate_Gateway_WETHAddressUnchanged") onlyOnRoninNetworkOrLocal {
    (TNetwork prevNetwork, uint256 prevForkId) = switchTo(companionNetwork);
    uint256 snapshotId = vm.snapshot();

    assertEq(address(ethWETH), address(IMainchainGatewayV3(ethGW).wrappedNativeToken()), "WETH address should not change");

    vm.revertTo(snapshotId);
    switchBack(prevNetwork, prevForkId);
  }

  function validate_Gateway_RevertIf_DuplicatedSigs_Withdraw_ERC20()
    private
    onPostCheck("validate_Gateway_RevertIf_DuplicatedSigs_Withdraw_ERC20")
    onlyOnRoninNetworkOrLocal
  {
    withdrawReq.recipientAddr = makeAddr("mainchain-recipient");
    withdrawReq.tokenAddr = address(ronERC20);
    withdrawReq.info.erc = TokenStandard.ERC20;
    withdrawReq.info.id = 0;
    withdrawReq.info.quantity = 1 ether;

    vm.prank(user);
    ronERC20.approve(ronGW, withdrawReq.info.quantity);

    vm.prank(user);
    vm.recordLogs();
    IRoninGatewayV3(ronGW).requestWithdrawalFor(withdrawReq, ethChainId);

    (LibTransfer.Receipt memory receipt, bytes32 receiptHash) = _getReceiptHash(ronGW, IRoninGatewayV3.WithdrawalRequested.selector);

    (TNetwork prevNetwork, uint256 prevForkId) = switchTo(companionNetwork);
    uint256 snapshotId = vm.snapshot();

    bytes32 receiptDigest = LibTransfer.receiptDigest(gwDomainHash, receiptHash);

    overrideMockBOs(ethBM);

    address[] memory bos = new address[](2);

    bos[0] = mockOps[0];
    bos[1] = mockOps[1];

    console.log("GW min vote weight:", IQuorum(ethGW).minimumVoteWeight());
    assertEq(IMainchainBridgeManager(ethBM).totalBridgeOperator(), 4, "Invalid total BOs");

    Signature[] memory sigs = _bulkSignReceipt(bos.extend(mockOps), receiptDigest);

    vm.expectRevert();
    IMainchainGatewayV3(ethGW).submitWithdrawal(receipt, sigs);

    vm.revertTo(snapshotId);
    switchBack(prevNetwork, prevForkId);
  }

  function validate_Gateway_RevertIf_UnsortedSigs_Withdraw_ERC20()
    private
    onPostCheck("validate_Gateway_RevertIf_UnsortedSigs_Withdraw_ERC20")
    onlyOnRoninNetworkOrLocal
  {
    withdrawReq.recipientAddr = makeAddr("mainchain-recipient");
    withdrawReq.tokenAddr = address(ronERC20);
    withdrawReq.info.erc = TokenStandard.ERC20;
    withdrawReq.info.id = 0;
    withdrawReq.info.quantity = 1 ether;

    vm.prank(user);
    ronERC20.approve(ronGW, withdrawReq.info.quantity);

    vm.prank(user);
    vm.recordLogs();
    IRoninGatewayV3(ronGW).requestWithdrawalFor(withdrawReq, ethChainId);

    (LibTransfer.Receipt memory receipt, bytes32 receiptHash) = _getReceiptHash(ronGW, IRoninGatewayV3.WithdrawalRequested.selector);

    (TNetwork prevNetwork, uint256 prevForkId) = switchTo(companionNetwork);
    uint256 snapshotId = vm.snapshot();

    bytes32 receiptDigest = LibTransfer.receiptDigest(gwDomainHash, receiptHash);

    overrideMockBOs(ethBM);

    Signature[] memory sigs = new Signature[](mockOps.length);

    for (uint256 i; i < mockOps.length; ++i) {
      (uint8 v, bytes32 r, bytes32 s) = vm.sign(mockOps[i], receiptDigest);
      sigs[i] = Signature(v, r, s);
    }

    if (uint160(mockOps[0]) < uint160(mockOps[1])) {
      // Swap if sorted
      Signature memory temp = sigs[0];
      sigs[0] = sigs[1];
      sigs[1] = temp;

      // Swap the mock ops
      address tempOp = mockOps[0];
      mockOps[0] = mockOps[1];
      mockOps[1] = tempOp;

      // Swap the mock gvs
      address tempGv = mockGvs[0];
      mockGvs[0] = mockGvs[1];
      mockGvs[1] = tempGv;
    }

    console.log("GW min vote weight:", IQuorum(ethGW).minimumVoteWeight());
    assertEq(IMainchainBridgeManager(ethBM).totalBridgeOperator(), 4, "Invalid total BOs");

    vm.expectRevert();
    IMainchainGatewayV3(ethGW).submitWithdrawal(receipt, sigs);

    vm.revertTo(snapshotId);
    switchBack(prevNetwork, prevForkId);
  }

  function validate_HasBridgeManager() private onPostCheck("validate_HasBridgeManager") onlyOnRoninNetworkOrLocal {
    assertEq(ronBM.getProxyAdmin(), ronBM, "Invalid ProxyAdmin in RoninBridgeManager, expected self");
    assertEq(IHasContracts(ronGW).getContract(ContractType.BRIDGE_MANAGER), ronBM, "Invalid RoninBridgeManager in ronGW");
    assertEq(IHasContracts(brTk).getContract(ContractType.BRIDGE_MANAGER), ronBM, "Invalid RoninBridgeManager in bridgeTracking");
    assertEq(IHasContracts(brRw).getContract(ContractType.BRIDGE_MANAGER), ronBM, "Invalid RoninBridgeManager in bridgeReward");
    assertEq(IHasContracts(brSl).getContract(ContractType.BRIDGE_MANAGER), ronBM, "Invalid RoninBridgeManager in bridgeSlash");

    (TNetwork prevNetwork, uint256 prevForkId) = switchTo(companionNetwork);
    uint256 snapshotId = vm.snapshot();

    assertEq(ethBM.getProxyAdmin(), ethBM, "Invalid ProxyAdmin in MainchainBridgeManager, expected self");
    assertEq(IHasContracts(ethGW).getContract(ContractType.BRIDGE_MANAGER), ethBM, "Invalid MainchainBridgeManager in ethGW");

    vm.revertTo(snapshotId);
    switchBack(prevNetwork, prevForkId);
  }

  function validate_Gateway_Deposit_ERC20() private onPostCheck("validate_Gateway_Deposit_ERC20") onlyOnRoninNetworkOrLocal {
    depositReq.recipientAddr = makeAddr("ronin-recipient");
    depositReq.tokenAddr = address(ethERC20);
    depositReq.info.erc = TokenStandard.ERC20;
    depositReq.info.id = 0;
    depositReq.info.quantity = 1 ether;

    (TNetwork prevNetwork, uint256 prevForkId) = switchTo(companionNetwork);
    uint256 snapshotId = vm.snapshot();

    vm.prank(user);
    ethERC20.approve(ethGW, depositReq.info.quantity);

    vm.prank(user);
    vm.recordLogs();
    IMainchainGatewayV3(ethGW).requestDepositFor(depositReq);

    (LibTransfer.Receipt memory receipt,) = _getReceiptHash(ethGW, IMainchainGatewayV3.DepositRequested.selector);

    vm.revertTo(snapshotId);
    switchBack(prevNetwork, prevForkId);

    overrideMockBOs(ronBM);

    uint256 minVoteRequired = _calcMinSigOrVoteRequired(ronBM, ronGW);
    assertTrue(minVoteRequired > 1, "Invalid test setup");

    for (uint256 i; i < minVoteRequired; ++i) {
      vm.prank(mockOps[i]);
      IRoninGatewayV3(ronGW).depositFor(receipt);
    }
  }

  function validate_Gateway_RevertIf_InsufficientThreshold_Deposit_ERC20()
    private
    onPostCheck("validate_Gateway_RevertIf_InsufficientThreshold_Deposit_ERC20")
    onlyOnRoninNetworkOrLocal
  {
    depositReq.recipientAddr = makeAddr("ronin-recipient");
    depositReq.tokenAddr = address(ethERC20);
    depositReq.info.erc = TokenStandard.ERC20;
    depositReq.info.id = 0;
    depositReq.info.quantity = 1 ether;

    (TNetwork prevNetwork, uint256 prevForkId) = switchTo(companionNetwork);
    uint256 snapshotId = vm.snapshot();

    vm.prank(user);
    ethERC20.approve(ethGW, depositReq.info.quantity);

    vm.prank(user);
    vm.recordLogs();
    IMainchainGatewayV3(ethGW).requestDepositFor(depositReq);

    (LibTransfer.Receipt memory receipt,) = _getReceiptHash(ethGW, IMainchainGatewayV3.DepositRequested.selector);

    vm.revertTo(snapshotId);
    switchBack(prevNetwork, prevForkId);

    overrideMockBOs(ronBM);

    uint256 minVW = IQuorum(ronGW).minimumVoteWeight();
    uint256 defaultVW = IBridgeManager(ronBM).getTotalWeight() / IBridgeManager(ronBM).totalBridgeOperator();
    uint256 minVoteRequired = minVW / defaultVW + 1;
    uint256 unmetVoteCount = minVoteRequired - 1;
    assertTrue(unmetVoteCount > 1, "Invalid test setup");

    for (uint256 i; i < unmetVoteCount; ++i) {
      vm.prank(mockOps[i]);
      IRoninGatewayV3(ronGW).depositFor(receipt);
    }
  }

  function validate_Gateway_RevertIf_InvalidSignature_Withdraw_ERC20()
    private
    onPostCheck("validate_Gateway_RevertIf_InvalidSignature_Withdraw_ERC20")
    onlyOnRoninNetworkOrLocal
  {
    withdrawReq.recipientAddr = makeAddr("malicious-recipient");
    withdrawReq.tokenAddr = address(ronERC20);
    withdrawReq.info.erc = TokenStandard.ERC20;
    withdrawReq.info.id = 0;
    withdrawReq.info.quantity = 1 ether;

    vm.prank(user);
    ronERC20.approve(ronGW, withdrawReq.info.quantity);

    vm.prank(user);
    vm.recordLogs();
    IRoninGatewayV3(ronGW).requestWithdrawalFor(withdrawReq, ethChainId);

    (LibTransfer.Receipt memory receipt, bytes32 receiptHash) = _getReceiptHash(ronGW, IRoninGatewayV3.WithdrawalRequested.selector);

    (TNetwork prevNetwork, uint256 prevForkId) = switchTo(companionNetwork);
    uint256 snapshotId = vm.snapshot();

    bytes32 receiptDigest = LibTransfer.receiptDigest(gwDomainHash, receiptHash);

    (address invalidSigner, uint256 invalidPK) = makeAddrAndKey(string.concat("invalid-signer-", vm.toString(vm.unixTime())));
    vm.rememberKey(invalidPK);
    (uint8 v, bytes32 r, bytes32 s) = vm.sign(invalidSigner, receiptDigest);
    Signature[] memory sigs = new Signature[](1);
    sigs[0] = Signature(v, r, s);

    vm.expectRevert();
    IMainchainGatewayV3(ethGW).submitWithdrawal(receipt, sigs);

    vm.revertTo(snapshotId);
    switchBack(prevNetwork, prevForkId);
  }

  function validate_Gateway_RevertIf_InsufficientThreshold_Withdraw_ERC20()
    private
    onPostCheck("validate_Gateway_RevertIf_InsufficientThreshold_Withdraw_ERC20")
    onlyOnRoninNetworkOrLocal
  {
    withdrawReq.recipientAddr = makeAddr("mainchain-recipient");
    withdrawReq.tokenAddr = address(ronERC20);
    withdrawReq.info.erc = TokenStandard.ERC20;
    withdrawReq.info.id = 0;
    withdrawReq.info.quantity = 1 ether;

    vm.prank(user);
    ronERC20.approve(ronGW, withdrawReq.info.quantity);

    vm.prank(user);
    vm.recordLogs();
    IRoninGatewayV3(ronGW).requestWithdrawalFor(withdrawReq, ethChainId);

    (LibTransfer.Receipt memory receipt, bytes32 receiptHash) = _getReceiptHash(ronGW, IRoninGatewayV3.WithdrawalRequested.selector);

    bytes32 receiptDigest = LibTransfer.receiptDigest(gwDomainHash, receiptHash);

    (TNetwork prevNetwork, uint256 prevForkId) = switchTo(companionNetwork);
    uint256 snapshotId = vm.snapshot();

    overrideMockBOs(ethBM);

    uint256 minSigRequired = _calcMinSigOrVoteRequired(ethBM, ethGW);
    uint256 unmetSigCount = minSigRequired - 1;
    assertTrue(unmetSigCount >= 1, "Invalid test setup");

    Signature[] memory sigs = _bulkSignReceipt(mockOps, receiptDigest);

    assembly {
      mstore(sigs, unmetSigCount)
    }

    vm.expectRevert();
    IMainchainGatewayV3(ethGW).submitWithdrawal(receipt, sigs);

    vm.revertTo(snapshotId);
    switchBack(prevNetwork, prevForkId);
  }

  function validate_Gateway_Withdraw_ERC20() private onPostCheck("validate_Gateway_Withdraw_ERC20") onlyOnRoninNetworkOrLocal {
    withdrawReq.recipientAddr = makeAddr("mainchain-recipient");
    withdrawReq.tokenAddr = address(ronERC20);
    withdrawReq.info.erc = TokenStandard.ERC20;
    withdrawReq.info.id = 0;
    withdrawReq.info.quantity = 1 ether;

    vm.prank(user);
    ronERC20.approve(ronGW, withdrawReq.info.quantity);

    vm.prank(user);
    vm.recordLogs();
    IRoninGatewayV3(ronGW).requestWithdrawalFor(withdrawReq, ethChainId);

    (LibTransfer.Receipt memory receipt, bytes32 receiptHash) = _getReceiptHash(ronGW, IRoninGatewayV3.WithdrawalRequested.selector);

    bytes32 receiptDigest = LibTransfer.receiptDigest(gwDomainHash, receiptHash);

    (TNetwork prevNetwork, uint256 prevForkId) = switchTo(companionNetwork);
    uint256 snapshotId = vm.snapshot();

    overrideMockBOs(ethBM);
    Signature[] memory sigs = _bulkSignReceipt(mockOps, receiptDigest);

    IMainchainGatewayV3(ethGW).submitWithdrawal(receipt, sigs);

    vm.revertTo(snapshotId);
    switchBack(prevNetwork, prevForkId);
  }

  function _calcMinSigOrVoteRequired(address bm, address gw) private view returns (uint256 minVoteOrSig) {
    uint256 minVW = IQuorum(gw).minimumVoteWeight();
    uint256 defaultVW = IBridgeManager(bm).getTotalWeight() / IBridgeManager(bm).totalBridgeOperator();
    minVoteOrSig = (minVW / defaultVW) + 1;
  }

  function _bulkSignReceipt(address[] memory signers, bytes32 receiptDigest) private pure returns (Signature[] memory sigs) {
    LibArray.inplaceAscSort(signers);

    sigs = new Signature[](signers.length);

    for (uint256 i; i < signers.length; ++i) {
      (uint8 v, bytes32 r, bytes32 s) = vm.sign(signers[i], receiptDigest);
      sigs[i] = Signature(v, r, s);
    }
  }

  function _concat(Signature[] memory a, Signature[] memory b) private pure returns (Signature[] memory c) {
    c = new Signature[](a.length + b.length);

    for (uint256 i; i < a.length; ++i) {
      c[i] = a[i];
    }

    for (uint256 i; i < b.length; ++i) {
      c[a.length + i] = b[i];
    }
  }

  function _getReceiptHash(address emitter, bytes32 eventTopic) private returns (LibTransfer.Receipt memory receipt, bytes32 receiptHash) {
    Vm.Log[] memory recordedLogs = vm.getRecordedLogs();

    for (uint256 i; i < recordedLogs.length; ++i) {
      if (recordedLogs[i].emitter == emitter && recordedLogs[i].topics[0] == eventTopic) {
        (receiptHash, receipt) = abi.decode(recordedLogs[i].data, (bytes32, LibTransfer.Receipt));
      }
    }
  }
}
