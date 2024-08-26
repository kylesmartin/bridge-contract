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

abstract contract PostCheck_Gateway_Quorum is BasePostCheck {
  using LibArray for *;
  using LibCompanionNetwork for *;

  function _validate_Gateway_Quorum() internal {
    // -------------- Gateway Quorum --------------
    validate_NonZero_MinimumVoteWeight_Gateway();
    validate_Valid_Threshold_Gateway();
  }

  function validate_Valid_Threshold_Gateway() private onlyOnRoninNetworkOrLocal onPostCheck("validate_Valid_Threshold_Gateway") {
    (uint256 num, uint256 denom) = IQuorum(ronGW).getThreshold();
    assertTrue(num > 0 && denom > 0, "Ronin: Gateway's Threshold must be greater than 0");
    assertTrue(num <= denom, "Ronin: Gateway's Threshold numerator must be less than or equal to denominator");
    TNetwork currNetwork = network();

    (, TNetwork companionNetwork) = currNetwork.companionNetworkData();
    (TNetwork prevNetwork, uint256 prevForkId) = switchTo(companionNetwork);

    (num, denom) = IQuorum(ethGW).getThreshold();
    assertTrue(num > 0 && denom > 0, "Mainchain: Gateway's Threshold must be greater than 0");
    assertTrue(num <= denom, "Mainchain: Gateway's Threshold numerator must be less than or equal to denominator");

    switchBack(prevNetwork, prevForkId);
  }

  function validate_NonZero_MinimumVoteWeight_Gateway() private onlyOnRoninNetworkOrLocal onPostCheck("validate_NonZero_Threshold_Gateway") {
    assertTrue(IQuorum(ronGW).minimumVoteWeight() > 0, "Ronin: Gateway's Minimum vote weight must be greater than 0");
    TNetwork currNetwork = network();

    (, TNetwork companionNetwork) = currNetwork.companionNetworkData();
    (TNetwork prevNetwork, uint256 prevForkId) = switchTo(companionNetwork);

    assertTrue(IQuorum(ethGW).minimumVoteWeight() > 0, "Mainchain: Gateway's Minimum vote weight must be greater than 0");

    switchBack(prevNetwork, prevForkId);
  }
}
