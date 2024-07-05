pragma solidity ^0.8.19;

import { LibCompanionNetwork } from "script/shared/libraries/LibCompanionNetwork.sol";
import { Network, TNetwork } from "../../utils/Network.sol";
import { console2 } from "forge-std/console2.sol";
import { LibProposal } from "script/shared/libraries/LibProposal.sol";
import { Proposal } from "@ronin/contracts/libraries/Proposal.sol";
import { Contract } from "../../utils/Contract.sol";
import { MainchainBridgeManager } from "@ronin/contracts/mainchain/MainchainBridgeManager.sol";
import "./factory-maptoken-roninchain.s.sol";

abstract contract Factory__MapTokensRonin_Testnet is Factory__MapTokensRoninchain {
  using LibCompanionNetwork for *;

  function setUp() public override {
    super.setUp();
    _roninBridgeManager = RoninBridgeManager(config.getAddressFromCurrentNetwork(Contract.RoninBridgeManager.key()));
    _roninGatewayV3 = config.getAddressFromCurrentNetwork(Contract.RoninGatewayV3.key());
    _specifiedCaller = _initCaller();
  }

  function _initGovernors() internal virtual returns (address[] memory);

  function run() public virtual override {
    address[] memory mGovernors = _initGovernors();

    for (uint256 i; i < mGovernors.length; ++i) {
      _governors.push(mGovernors[i]);
    }

    Proposal.ProposalDetail memory proposal = _createAndVerifyProposalOnRonin();
    _proposeAndExecuteProposal(proposal);
  }
}
