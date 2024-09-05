// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import { IBridgeManager } from "@ronin/contracts/interfaces/bridge/IBridgeManager.sol";
import { IQuorum } from "@ronin/contracts/interfaces/IQuorum.sol";
import { BasePostCheck } from "script/post-check/BasePostCheck.s.sol";
import { LibArray } from "script/shared/libraries/LibArray.sol";
import { Contract } from "script/utils/Contract.sol";
import { TNetwork } from "@fdk/types/Types.sol";
import { Network } from "script/utils/Network.sol";
import { LibCompanionNetwork } from "script/shared/libraries/LibCompanionNetwork.sol";

abstract contract PostCheck_BridgeManager_Quorum is BasePostCheck {
  using LibArray for *;
  using LibCompanionNetwork for *;

  /// @dev Expected vote weight for BridgeManager's Operator
  uint256 private constant expectedVW = 100;
  /// @dev Expected minimum vote weight for BridgeManager
  uint256 private constant expectedMinTotalWeight = 100 * 3;

  function _validate_BridgeManager_Quorum() internal {
    // -------------- BridgeManager Quorum --------------
    validate_Equal_VoteWeight_Operator_BridgeManager();
    validate_NonZero_MinimumVoteWeight_BridgeManager();
    validate_GreaterOrEqualMinExpected_TotalWeight_BridgeManager();
    validate_Valid_Threshold_BridgeManager();
  }

  function validate_Equal_VoteWeight_Operator_BridgeManager() private onlyOnRoninNetworkOrLocal onPostCheck("validate_Equal_VoteWeight_Operator_BridgeManager") {
    address[] memory operators = IBridgeManager(ronBM).getBridgeOperators();
    for (uint256 i = 0; i < operators.length; i++) {
      uint256 voteWeight = IBridgeManager(ronBM).getBridgeOperatorWeight(operators[i]);
      assertTrue(voteWeight == expectedVW, "Ronin: BridgeManager's Operator vote weight must be equal to 100");
    }

    TNetwork currNetwork = network();

    (, TNetwork companionNetwork) = currNetwork.companionNetworkData();
    (TNetwork prevNetwork, uint256 prevForkId) = switchTo(companionNetwork);

    operators = IBridgeManager(ethBM).getBridgeOperators();
    for (uint256 i = 0; i < operators.length; i++) {
      uint256 voteWeight = IBridgeManager(ethBM).getBridgeOperatorWeight(operators[i]);
      assertTrue(voteWeight == expectedVW, "Mainchain: BridgeManager's Operator vote weight must be equal to 100");
    }

    switchBack(prevNetwork, prevForkId);
  }

  function validate_Valid_Threshold_BridgeManager() private onlyOnRoninNetworkOrLocal onPostCheck("validate_valid_Threshold_BridgeManager") {
    (uint256 num, uint256 denom) = IQuorum(ronBM).getThreshold();
    assertTrue(num > 0 && denom > 0, "Ronin: BridgeManager's Threshold must be greater than 0");
    assertTrue(num <= denom, "Ronin: BridgeManager's Threshold numerator must be less than or equal to denominator");
    TNetwork currNetwork = network();

    (, TNetwork companionNetwork) = currNetwork.companionNetworkData();
    (TNetwork prevNetwork, uint256 prevForkId) = switchTo(companionNetwork);

    (num, denom) = IQuorum(ethBM).getThreshold();
    assertTrue(num > 0 && denom > 0, "Mainchain: BridgeManager's Threshold must be greater than 0");
    assertTrue(num <= denom, "Mainchain: BridgeManager's Threshold numerator must be less than or equal to denominator");

    switchBack(prevNetwork, prevForkId);
  }

  function validate_NonZero_MinimumVoteWeight_BridgeManager() private onlyOnRoninNetworkOrLocal onPostCheck("validate_NonZero_MinimumVoteWeight") {
    assertTrue(IQuorum(ronBM).minimumVoteWeight() > 0, "Ronin: BridgeManager's Minimum vote weight must be greater than 0");
    TNetwork currNetwork = network();

    (, TNetwork companionNetwork) = currNetwork.companionNetworkData();
    (TNetwork prevNetwork, uint256 prevForkId) = switchTo(companionNetwork);

    assertTrue(IQuorum(ethBM).minimumVoteWeight() > 0, "Mainchain: BridgeManager's Minimum vote weight must be greater than 0");

    switchBack(prevNetwork, prevForkId);
  }

  function validate_GreaterOrEqualMinExpected_TotalWeight_BridgeManager()
    private
    onlyOnRoninNetworkOrLocal
    onPostCheck("validate_GreaterOrEqualMinExpected_TotalWeight_BridgeManager")
  {
    assertTrue(IBridgeManager(ronBM).getTotalWeight() > 0, "Ronin: BridgeManager's Total weight must be greater than 0");
    TNetwork currNetwork = network();

    (, TNetwork companionNetwork) = currNetwork.companionNetworkData();
    (TNetwork prevNetwork, uint256 prevForkId) = switchTo(companionNetwork);

    assertTrue(
      IBridgeManager(ethBM).getTotalWeight() > expectedMinTotalWeight, "Mainchain: BridgeManager's Total weight must be greater than `expectedMinTotalWeight`"
    );

    switchBack(prevNetwork, prevForkId);
  }
}
