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

  function _validate_BridgeManager_Quorum() internal {
    // -------------- BridgeManager Quorum --------------
    validate_NonZero_MinimumVoteWeight_BridgeManager();
    validate_NonZero_TotalWeight_BridgeManager();
    validate_Valid_Threshold_BridgeManager();

    // -------------- Gateway Quorum --------------
    validate_NonZero_MinimumVoteWeight_Gateway();
    validate_NonZero_TotalWeight_Gateway();
    validate_Valid_Threshold_Gateway();
  }

  function validate_Valid_Threshold_BridgeManager() internal onlyOnRoninNetworkOrLocal onPostCheck("validate_valid_Threshold_BridgeManager") {
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

  function validate_Valid_Threshold_Gateway() internal onlyOnRoninNetworkOrLocal onPostCheck("validate_Valid_Threshold_Gateway") {
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

  function validate_NonZero_TotalWeight_Gateway() internal onlyOnRoninNetworkOrLocal onPostCheck("validate_NonZero_TotalWeight_Gateway") {
    assertTrue(IBridgeManager(ronGW).getTotalWeight() > 0, "Ronin: Gateway's Total weight must be greater than 0");
    TNetwork currNetwork = network();

    (, TNetwork companionNetwork) = currNetwork.companionNetworkData();
    (TNetwork prevNetwork, uint256 prevForkId) = switchTo(companionNetwork);

    assertTrue(IBridgeManager(ethGW).getTotalWeight() > 0, "Mainchain: Gateway's Total weight must be greater than 0");

    switchBack(prevNetwork, prevForkId);
  }

  function validate_NonZero_MinimumVoteWeight_Gateway() internal onlyOnRoninNetworkOrLocal onPostCheck("validate_NonZero_Threshold_Gateway") {
    assertTrue(IQuorum(ronGW).minimumVoteWeight() > 0, "Ronin: Gateway's Minimum vote weight must be greater than 0");
    TNetwork currNetwork = network();

    (, TNetwork companionNetwork) = currNetwork.companionNetworkData();
    (TNetwork prevNetwork, uint256 prevForkId) = switchTo(companionNetwork);

    assertTrue(IQuorum(ethGW).minimumVoteWeight() > 0, "Mainchain: Gateway's Minimum vote weight must be greater than 0");

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

  function validate_NonZero_TotalWeight_BridgeManager() private onlyOnRoninNetworkOrLocal onPostCheck("validate_NonZero_TotalWeight_BridgeManager") {
    assertTrue(IBridgeManager(ronBM).getTotalWeight() > 0, "Ronin: BridgeManager's Total weight must be greater than 0");
    TNetwork currNetwork = network();

    (, TNetwork companionNetwork) = currNetwork.companionNetworkData();
    (TNetwork prevNetwork, uint256 prevForkId) = switchTo(companionNetwork);

    assertTrue(IBridgeManager(ethBM).getTotalWeight() > 0, "Mainchain: BridgeManager's Total weight must be greater than 0");

    switchBack(prevNetwork, prevForkId);
  }
}
