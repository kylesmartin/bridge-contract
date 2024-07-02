// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import { LibCompanionNetwork } from "script/shared/libraries/LibCompanionNetwork.sol";
import { Network, TNetwork } from "../../utils/Network.sol";
import { console2 } from "forge-std/console2.sol";
import { LibProposal } from "script/shared/libraries/LibProposal.sol";
import { Proposal } from "@ronin/contracts/libraries/Proposal.sol";
import { Contract } from "../../utils/Contract.sol";
import { MainchainBridgeManager } from "@ronin/contracts/mainchain/MainchainBridgeManager.sol";
import "./factory-maptoken-mainchain.s.sol";

abstract contract Factory__MapTokensMainchainSepolia is Factory__MapTokensMainchain {
  using LibCompanionNetwork for *;

  function setUp() public override {
    super.setUp();
    _mainchainGatewayV3 = config.getAddressFromCurrentNetwork(Contract.MainchainGatewayV3.key());
    _mainchainBridgeManager = config.getAddressFromCurrentNetwork(Contract.MainchainBridgeManager.key());
  }

  function _initGovernorPKs() internal virtual returns (uint256[] memory);
  function _initGovernors() internal virtual returns (address[] memory);

  function run() public virtual override {
    address[] memory governorsM = _initGovernors();
    uint256[] memory governorsPksM = _initGovernorPKs();

    for (uint256 i; i < governorsM.length; ++i) {
      _governors.push(governorsM[i]);
      _governorPKs.push(governorsPksM[i]);
    }
    _cheatStorage(_governors);

    uint256 chainId = block.chainid;
    uint256 nonce = MainchainBridgeManager(_mainchainBridgeManager).round(chainId) + 1;
    Proposal.ProposalDetail memory proposal = _createAndVerifyProposal(chainId, nonce);
    _relayProposal(proposal);
  }
}
