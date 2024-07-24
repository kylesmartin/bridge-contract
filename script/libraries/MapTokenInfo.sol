// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import { LibTokenInfo, TokenStandard } from "@ronin/contracts/libraries/LibTokenInfo.sol";

struct MapTokenInfo {
  address roninToken;
  address mainchainToken;
  TokenStandard standard;
  // This properties is used for ERC20 only.
  // Config on mainchain
  uint256 minThreshold;
  // Config on ronin chain
  uint256 highTierThreshold;
  uint256 lockedThreshold;
  uint256 dailyWithdrawalLimit;
  uint256 unlockFeePercentages;
}
