// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import { console2 } from "forge-std/console2.sol";
import { StdStyle } from "forge-std/StdStyle.sol";
import { MainchainBridgeManager } from "@ronin/contracts/mainchain/MainchainBridgeManager.sol";
import { IMainchainGatewayV3 } from "@ronin/contracts/interfaces/IMainchainGatewayV3.sol";
import { GlobalProposal } from "@ronin/contracts/libraries/GlobalProposal.sol";
import { LibTokenInfo, TokenStandard } from "@ronin/contracts/libraries/LibTokenInfo.sol";
import { Contract } from "../utils/Contract.sol";
import { Network } from "../utils/Network.sol";
import { Contract } from "../utils/Contract.sol";
import { ISharedArgument } from "../interfaces/ISharedArgument.sol";
import "@ronin/contracts/mainchain/MainchainBridgeManager.sol";
import "@ronin/contracts/mainchain/MainchainGatewayV3.sol";
import "@ronin/contracts/libraries/Proposal.sol";
import "@ronin/contracts/libraries/Ballot.sol";

import { LibProxy } from "@fdk/libraries/LibProxy.sol";
import { DefaultContract } from "@fdk/utils/DefaultContract.sol";
import { MockSLP } from "@ronin/contracts/mocks/token/MockSLP.sol";
import { SLPDeploy } from "@ronin/script/contracts/token/SLPDeploy.s.sol";
import { MainchainBridgeAdminUtils } from "test/helpers/MainchainBridgeAdminUtils.t.sol";
import "@ronin/script/contracts/MainchainBridgeManagerDeploy.s.sol";
import "@ronin/script/contracts/MainchainWethUnwrapperDeploy.s.sol";

import "./20240716-helper.s.sol";
import "./20240716-operators-key.s.sol";
import "./wbtc-threshold.s.sol";
import "../Migration.s.sol";

contract Migration__20240716_P3_UpgradeBridgeMainchain is Migration, Migration__20240716_GovernorsKey, Migration__MapToken_WBTC_Threshold {
  MainchainBridgeManager _currMainchainBridgeManager;
  MainchainBridgeManager _newMainchainBridgeManager;

  address private _governor;

  function setUp() public virtual override {
    super.setUp();
  }

  function run() public virtual onlyOn(Network.EthMainnet.key()) {
    // CONFIG.setAddress(network(), DefaultContract.ProxyAdmin.key(), TESTNET_ADMIN);

    _currMainchainBridgeManager = MainchainBridgeManager(config.getAddressFromCurrentNetwork(Contract.MainchainBridgeManager.key()));

    _governor = 0xd24D87DDc1917165435b306aAC68D99e0F49A3Fa;

    // _changeTempAdmin();
    _deployMainchainBridgeManager();
    _upgradeBridgeMainchain();
  }

  // function _changeTempAdmin() internal {
  //   address pauseEnforcerProxy = config.getAddressFromCurrentNetwork(Contract.MainchainPauseEnforcer.key());
  //   address mainchainGatewayV3Proxy = config.getAddressFromCurrentNetwork(Contract.MainchainGatewayV3.key());

  //   vm.startBroadcast(TESTNET_ADMIN);
  //   address(pauseEnforcerProxy).call(abi.encodeWithSignature("changeAdmin(address)", _currMainchainBridgeManager));
  //   address(mainchainGatewayV3Proxy).call(abi.encodeWithSignature("changeAdmin(address)", _currMainchainBridgeManager));
  //   vm.stopBroadcast();
  // }

  function _deployMainchainBridgeManager() internal returns (address mainchainBM) {
    ISharedArgument.SharedParameter memory param;

    {
      (address[] memory currGovernors, address[] memory currOperators, uint96[] memory currWeights) = _currMainchainBridgeManager.getFullBridgeOperatorInfos();
      uint totalCurrGovernors = currGovernors.length;
      param.roninBridgeManager.bridgeOperators = new address[](totalCurrGovernors);
      param.roninBridgeManager.governors = new address[](totalCurrGovernors);
      param.roninBridgeManager.voteWeights = new uint96[](totalCurrGovernors);

      for (uint i = 0; i < totalCurrGovernors; i++) {
        param.roninBridgeManager.bridgeOperators[i] = currOperators[i];
        param.roninBridgeManager.governors[i] = currGovernors[i];
        param.roninBridgeManager.voteWeights[i] = currWeights[i];
      }
    }

    param.mainchainBridgeManager.num = 7;
    param.mainchainBridgeManager.denom = 10;
    param.mainchainBridgeManager.roninChainId = 2020;
    param.mainchainBridgeManager.expiryDuration = 60 * 60 * 24 * 14; // 14 days
    param.mainchainBridgeManager.bridgeContract = config.getAddressFromCurrentNetwork(Contract.MainchainGatewayV3.key());

    param.mainchainBridgeManager.targetOptions = new GlobalProposal.TargetOption[](2);
    param.mainchainBridgeManager.targetOptions[0] = GlobalProposal.TargetOption.GatewayContract;
    param.mainchainBridgeManager.targetOptions[1] = GlobalProposal.TargetOption.PauseEnforcer;

    param.mainchainBridgeManager.targets = new address[](2);
    param.mainchainBridgeManager.targets[0] = config.getAddressFromCurrentNetwork(Contract.MainchainGatewayV3.key());
    param.mainchainBridgeManager.targets[1] = config.getAddressFromCurrentNetwork(Contract.MainchainPauseEnforcer.key());

    _newMainchainBridgeManager = MainchainBridgeManager(
      new MainchainBridgeManagerDeploy().overrideArgs(
        abi.encodeCall(
          _newMainchainBridgeManager.initialize,
          (
            param.mainchainBridgeManager.num,
            param.mainchainBridgeManager.denom,
            param.mainchainBridgeManager.roninChainId,
            param.mainchainBridgeManager.bridgeContract,
            new address[](0),
            param.mainchainBridgeManager.bridgeOperators,
            param.mainchainBridgeManager.governors,
            param.mainchainBridgeManager.voteWeights,
            param.mainchainBridgeManager.targetOptions,
            param.mainchainBridgeManager.targets
          )
        )
      ).run()
    );

    address proxyAdmin = LibProxy.getProxyAdmin(payable(address(_newMainchainBridgeManager)));
    vm.broadcast(proxyAdmin);
    TransparentUpgradeableProxy(payable(address(_newMainchainBridgeManager))).changeAdmin(address(_currMainchainBridgeManager));
  }

  function _upgradeBridgeMainchain() internal {
    address weth = config.getAddressFromCurrentNetwork(Contract.WETH.key());
    address wethUnwrapper = new MainchainWethUnwrapperDeploy().overrideArgs(abi.encode(weth)).run();

    address pauseEnforcerLogic = _deployLogic(Contract.MainchainPauseEnforcer.key());
    address mainchainGatewayV3Logic = _deployLogic(Contract.MainchainGatewayV3.key());

    address pauseEnforcerProxy = config.getAddressFromCurrentNetwork(Contract.MainchainPauseEnforcer.key());
    address mainchainGatewayV3Proxy = config.getAddressFromCurrentNetwork(Contract.MainchainGatewayV3.key());

    ISharedArgument.SharedParameter memory param;
    param.mainchainBridgeManager.callbackRegisters = new address[](1);
    param.mainchainBridgeManager.callbackRegisters[0] = config.getAddressFromCurrentNetwork(Contract.MainchainGatewayV3.key());

    uint256 expiredTime = block.timestamp + 14 days;
    uint N = 6;
    address[] memory targets = new address[](N);
    uint256[] memory values = new uint256[](N);
    bytes[] memory calldatas = new bytes[](N);
    uint256[] memory gasAmounts = new uint256[](N);

    targets[0] = mainchainGatewayV3Proxy;
    targets[1] = mainchainGatewayV3Proxy;
    targets[2] = mainchainGatewayV3Proxy;
    targets[3] = mainchainGatewayV3Proxy;
    targets[4] = address(_newMainchainBridgeManager);
    targets[5] = address(_newMainchainBridgeManager);


    // Mapping WBTC calldata
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

      calldatas[0] =  abi.encodeWithSignature("functionDelegateCall(bytes)", abi.encodeCall(IMainchainGatewayV3.mapTokensAndThresholds, (mainchainTokens, roninTokens, standards, thresholds)));
    }

    calldatas[1] = abi.encodeWithSignature(
      "upgradeToAndCall(address,bytes)", mainchainGatewayV3Logic, abi.encodeWithSelector(MainchainGatewayV3.initializeV4.selector, wethUnwrapper)
    );
    calldatas[2] =
      abi.encodeWithSignature("functionDelegateCall(bytes)", (abi.encodeWithSignature("setContract(uint8,address)", 11, address(_newMainchainBridgeManager))));

    // Do all setting steps before migrating to change admin
    calldatas[3] = abi.encodeWithSignature("changeAdmin(address)", address(_newMainchainBridgeManager));
    calldatas[4] = abi.encodeWithSignature(
      "functionDelegateCall(bytes)", (abi.encodeWithSignature("registerCallbacks(address[])", param.mainchainBridgeManager.callbackRegisters))
    );
    calldatas[5] = abi.encodeWithSignature("changeAdmin(address)", address(_newMainchainBridgeManager));

    for (uint i; i < N; ++i) {
      gasAmounts[i] = 1_000_000;
    }

    LegacyProposalDetail memory proposal;
    proposal.nonce = _currMainchainBridgeManager.round(block.chainid) + 1;
    proposal.chainId = block.chainid;
    proposal.expiryTimestamp = expiredTime;
    proposal.targets = targets;
    proposal.values = values;
    proposal.calldatas = calldatas;
    proposal.gasAmounts = gasAmounts;

    _simulateProposal(proposal);

    // uint V = _voters.length + 1;
    // Ballot.VoteType[] memory supports_ = new Ballot.VoteType[](V);
    // for (uint i; i < V; ++i) {
    //   supports_[i] = Ballot.VoteType.For;
    // }

    // SignatureConsumer.Signature[] memory signatures = _generateSignaturesFor(getDomain(), hashLegacyProposal(proposal), _loadGovernorPKs(), Ballot.VoteType.For);

    // vm.broadcast(_governor);
    // address(_currMainchainBridgeManager).call{ gas: (proposal.targets.length + 1) * 1_000_000 }(
    //   abi.encodeWithSignature(
    //     "relayProposal((uint256,uint256,uint256,address[],uint256[],bytes[],uint256[]),uint8[],(uint8,bytes32,bytes32)[])", proposal, supports_, signatures
    //   )
    // );
  }

  function getDomain() public pure returns (bytes32) {
    return keccak256(
      abi.encode(
        keccak256("EIP712Domain(string name,string version,bytes32 salt)"),
        keccak256("BridgeAdmin"), // name hash
        keccak256("2"), // version hash
        keccak256(abi.encode("BRIDGE_ADMIN", 2020)) // salt
      )
    );
  }

  function _generateSignaturesFor(
    bytes32 domain,
    bytes32 proposalHash,
    uint256[] memory signerPKs,
    Ballot.VoteType support
  ) public view returns (SignatureConsumer.Signature[] memory sigs) {
    sigs = new SignatureConsumer.Signature[](signerPKs.length);

    for (uint256 i; i < signerPKs.length; i++) {
      bytes32 digest = ECDSA.toTypedDataHash(domain, Ballot.hash(proposalHash, support));
      sigs[i] = _sign(signerPKs[i], digest);
    }
  }

  function _sign(uint256 pk, bytes32 digest) internal pure returns (SignatureConsumer.Signature memory sig) {
    (uint8 v, bytes32 r, bytes32 s) = vm.sign(pk, digest);
    sig.v = v;
    sig.r = r;
    sig.s = s;
  }

  function hashLegacyProposal(LegacyProposalDetail memory proposal) public pure returns (bytes32 digest_) {
    bytes32 TYPE_HASH = 0xd051578048e6ff0bbc9fca3b65a42088dbde10f36ca841de566711087ad9b08a;

    uint256[] memory values = proposal.values;
    address[] memory targets = proposal.targets;
    bytes32[] memory calldataHashList = new bytes32[](proposal.calldatas.length);
    uint256[] memory gasAmounts = proposal.gasAmounts;

    for (uint256 i; i < calldataHashList.length; ++i) {
      calldataHashList[i] = keccak256(proposal.calldatas[i]);
    }

    assembly {
      let ptr := mload(0x40)
      mstore(ptr, TYPE_HASH)
      mstore(add(ptr, 0x20), mload(proposal)) // _proposal.nonce
      mstore(add(ptr, 0x40), mload(add(proposal, 0x20))) // _proposal.chainId
      mstore(add(ptr, 0x60), mload(add(proposal, 0x40))) // expiry timestamp

      let arrayHashed
      arrayHashed := keccak256(add(targets, 32), mul(mload(targets), 32)) // targetsHash
      mstore(add(ptr, 0x80), arrayHashed)
      arrayHashed := keccak256(add(values, 32), mul(mload(values), 32)) // _valuesHash
      mstore(add(ptr, 0xa0), arrayHashed)
      arrayHashed := keccak256(add(calldataHashList, 32), mul(mload(calldataHashList), 32)) // _calldatasHash
      mstore(add(ptr, 0xc0), arrayHashed)
      arrayHashed := keccak256(add(gasAmounts, 32), mul(mload(gasAmounts), 32)) // _gasAmountsHash
      mstore(add(ptr, 0xe0), arrayHashed)
      digest_ := keccak256(ptr, 0x100)
    }
  }

  function _simulateProposal(LegacyProposalDetail memory proposal) internal {
    Ballot.VoteType[] memory cheatingSupports = new Ballot.VoteType[](1);
    uint256[] memory cheatingPks = new uint256[](1);
    (address cheatingGov, uint256 cheatingGovPk) = makeAddrAndKey("Governor");

    cheatingSupports[0] = Ballot.VoteType.For;
    cheatingPks[0] = cheatingGovPk;
    SignatureConsumer.Signature[] memory cheatingSignatures = _generateSignaturesFor(getDomain(), hashLegacyProposal(proposal), cheatingPks, Ballot.VoteType.For);

    uint256 totalGas = 1_000_000;
    for (uint256 i; i < proposal.gasAmounts.length; ++i) {
      totalGas += proposal.gasAmounts[i];
    }

    _cheatWeightGovernor(IBridgeManager(_currMainchainBridgeManager), cheatingGov);

    vm.prank(cheatingGov);
    address(_currMainchainBridgeManager).call{ gas: totalGas }(
      abi.encodeWithSignature(
        "relayProposal((uint256,uint256,uint256,address[],uint256[],bytes[],uint256[]),uint8[],(uint8,bytes32,bytes32)[])", proposal, cheatingSupports, cheatingSignatures
      )
    );
  }

  function _cheatWeightGovernor(IBridgeManager manager, address gov) internal {
    bytes32 $ = keccak256(abi.encode(gov, 0x88547008e60f5748911f2e59feb3093b7e4c2e87b2dd69d61f112fcc932de8e3));
    bytes32 opAndWeight = vm.load(address(manager), $);

    uint256 totalWeight = manager.getTotalWeight();
    bytes32 newOpAndWeight = bytes32((totalWeight << 160) + uint160(uint256(opAndWeight)));
    vm.store(address(manager), $, newOpAndWeight);

    assert(manager.getGovernorWeight(gov) == totalWeight);
  }
}
