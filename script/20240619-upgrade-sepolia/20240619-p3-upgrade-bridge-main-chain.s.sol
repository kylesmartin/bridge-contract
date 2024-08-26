// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import { console } from "forge-std/console.sol";
import { StdStyle } from "forge-std/StdStyle.sol";
import { IMainchainBridgeManager } from "script/interfaces/IMainchainBridgeManager.sol";
import { IMainchainGatewayV3 } from "@ronin/contracts/interfaces/IMainchainGatewayV3.sol";
import { GlobalProposal } from "@ronin/contracts/libraries/GlobalProposal.sol";
import { LibTokenInfo, TokenStandard } from "@ronin/contracts/libraries/LibTokenInfo.sol";
import { Contract } from "../utils/Contract.sol";
import { Network } from "../utils/Network.sol";
import { Contract } from "../utils/Contract.sol";
import { ISharedArgument } from "../interfaces/ISharedArgument.sol";
import { IMainchainGatewayV3 } from "@ronin/contracts/interfaces/IMainchainGatewayV3.sol";
import "@ronin/contracts/libraries/Proposal.sol";
import "@ronin/contracts/libraries/Ballot.sol";

import { LibProxy } from "@fdk/libraries/LibProxy.sol";
import { DefaultContract } from "@fdk/utils/DefaultContract.sol";
import { MockSLP } from "@ronin/contracts/mocks/token/MockSLP.sol";
import { SLPDeploy } from "script/contracts/token/SLPDeploy.s.sol";
import { MainchainBridgeAdminUtils } from "test/helpers/MainchainBridgeAdminUtils.t.sol";
import "script/contracts/MainchainBridgeManagerDeploy.s.sol";
import "script/contracts/MainchainWethUnwrapperDeploy.s.sol";

import "../20240411-upgrade-v3.2.0-testnet/20240411-helper.s.sol";
import "./20240619-operators-key.s.sol";
import { Migration } from "../Migration.s.sol";

contract Migration__20240619_P3_UpgradeBridgeMainchain is Migration, Migration__20240619_GovernorsKey {
  IMainchainBridgeManager _mainchainBridgeManager;
  MainchainBridgeAdminUtils _mainchainProposalUtils;

  address private _governor;
  address[] private _voters;

  address TESTNET_ADMIN = 0x968D0Cd7343f711216817E617d3f92a23dC91c07;

  function setUp() public virtual override {
    super.setUp();
  }

  function run() public virtual onlyOn(Network.Sepolia.key()) {
    CONFIG.setAddress(network(), DefaultContract.ProxyAdmin.key(), TESTNET_ADMIN);

    _mainchainBridgeManager = IMainchainBridgeManager(loadContract(Contract.MainchainBridgeManager.key()));

    _governor = 0xd24D87DDc1917165435b306aAC68D99e0F49A3Fa;
    _voters.push(0xb033ba62EC622dC54D0ABFE0254e79692147CA26);
    _voters.push(0x087D08e3ba42e64E3948962dd1371F906D1278b9);
    _voters.push(0x52ec2e6BBcE45AfFF8955Da6410bb13812F4289F);

    _upgradeBridgeMainchain();
  }

  function _upgradeBridgeMainchain() internal {
    address mainchainGatewayV3Logic = _deployLogic(Contract.MainchainGatewayV3.key());
    address mainchainGatewayV3Proxy = loadContract(Contract.MainchainGatewayV3.key());

    ISharedArgument.SharedParameter memory param;
    param.mainchainBridgeManager.callbackRegisters = new address[](1);
    param.mainchainBridgeManager.callbackRegisters[0] = loadContract(Contract.MainchainGatewayV3.key());

    uint256 expiredTime = block.timestamp + 14 days;
    uint N = 1;
    address[] memory targets = new address[](N);
    uint256[] memory values = new uint256[](N);
    bytes[] memory calldatas = new bytes[](N);
    uint256[] memory gasAmounts = new uint256[](N);

    targets[0] = mainchainGatewayV3Proxy;
    calldatas[0] = abi.encodeWithSignature("upgradeTo(address)", mainchainGatewayV3Logic);
    gasAmounts[0] = 1_000_000;

    // ================ VERIFY AND EXECUTE PROPOSAL ===============

    address[] memory governors = new address[](4);
    governors[3] = 0xd24D87DDc1917165435b306aAC68D99e0F49A3Fa;
    governors[2] = 0xb033ba62EC622dC54D0ABFE0254e79692147CA26;
    governors[0] = 0x087D08e3ba42e64E3948962dd1371F906D1278b9;
    governors[1] = 0x52ec2e6BBcE45AfFF8955Da6410bb13812F4289F;

    Proposal.ProposalDetail memory proposal = Proposal.ProposalDetail({
      nonce: IMainchainBridgeManager(_mainchainBridgeManager).round(block.chainid) + 1,
      chainId: block.chainid,
      expiryTimestamp: expiredTime,
      executor: address(0),
      targets: targets,
      values: values,
      calldatas: calldatas,
      gasAmounts: gasAmounts
    });

    LegacyProposalDetail memory legacyProposal;
    legacyProposal.nonce = proposal.nonce;
    legacyProposal.chainId = proposal.chainId;
    legacyProposal.expiryTimestamp = proposal.expiryTimestamp;
    legacyProposal.targets = proposal.targets;
    legacyProposal.values = proposal.values;
    legacyProposal.calldatas = proposal.calldatas;
    legacyProposal.gasAmounts = proposal.gasAmounts;

    Ballot.VoteType[] memory supports_ = new Ballot.VoteType[](4);
    supports_[0] = Ballot.VoteType.For;
    supports_[1] = Ballot.VoteType.For;
    supports_[2] = Ballot.VoteType.For;
    supports_[3] = Ballot.VoteType.For;

    bytes32 proposalHash = hashLegacyProposal(legacyProposal);
    Signature[] memory signatures = _generateSignaturesFor(getDomain(), proposalHash, _loadGovernors(), supports_[0]);

    vm.broadcast(governors[0]);
    // 2_000_000 to assure tx.gasleft is bigger than the gas of the proposal.
    IMainchainBridgeManager(_mainchainBridgeManager).relayProposal{ gas: 2_000_000 }(proposal, supports_, signatures);
  }

  function getDomain() public pure returns (bytes32) {
    return keccak256(
      abi.encode(
        keccak256("EIP712Domain(string name,string version,bytes32 salt)"),
        keccak256("BridgeAdmin"), // name hash
        keccak256("2"), // version hash
        keccak256(abi.encode("BRIDGE_ADMIN", 2021)) // salt
      )
    );
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

  function _generateSignaturesFor(
    bytes32 domain,
    bytes32 proposalHash,
    address[] memory signers,
    Ballot.VoteType support
  ) public pure returns (Signature[] memory sigs) {
    sigs = new Signature[](signers.length);

    for (uint256 i; i < signers.length; i++) {
      bytes32 digest = ECDSA.toTypedDataHash(domain, Ballot.hash(proposalHash, support));
      sigs[i] = _sign(signers[i], digest);
    }
  }

  function _sign(address signer, bytes32 digest) internal pure returns (Signature memory sig) {
    (uint8 v, bytes32 r, bytes32 s) = vm.sign(signer, digest);
    sig.v = v;
    sig.r = r;
    sig.s = s;
  }
}
