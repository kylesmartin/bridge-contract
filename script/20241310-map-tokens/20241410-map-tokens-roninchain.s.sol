// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import { IRoninBridgeManager } from "script/interfaces/IRoninBridgeManager.sol";
import { Proposal } from "@ronin/contracts/libraries/Proposal.sol";

import { MapTokenConfig } from "script/20241310-map-tokens/MapTokenConfig.s.sol";
import { LibProposal } from "script/shared/libraries/LibProposal.sol";
import { Contract } from "script/utils/Contract.sol";

contract Migration__20241410_MapTokens_Roninchain is MapTokenConfig {
  address internal constant _SM_GOVERNOR = 0xe880802580a1fbdeF67ACe39D1B21c5b2C74f059;
  address internal constant _EXECUTOR = address(0);

  Proposal.ProposalDetail internal _proposal;
  IRoninBridgeManager internal _ronBM;

  function run() public virtual override {
    super.run();

    _ronBM = IRoninBridgeManager(loadContract(Contract.RoninBridgeManager.key()));
    uint256 expiry = block.timestamp + _DEFAULT_EXPIRY_DURATION;
    (address[] memory targets, uint256[] memory values, bytes[] memory callDatas, uint256[] memory gasAmounts) = getRoninMapData();
    uint256 nonce = _ronBM.round(block.chainid) + 1;
    _proposal = LibProposal.createProposal(address(_ronBM), nonce, expiry, targets, values, callDatas, gasAmounts);

    vm.broadcast(_SM_GOVERNOR);
    _ronBM.propose(block.chainid, expiry, _EXECUTOR, targets, values, callDatas, gasAmounts);
  }

  function _postCheck() internal virtual override {
    LibProposal.voteFor(_ronBM, _proposal);

    // super._postCheck();
  }
}
