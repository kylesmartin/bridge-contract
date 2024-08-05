// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

contract Migration__MapToken_WBTC_Threshold {
  address _wbtcRoninToken = address(0x7E73630F81647bCFD7B1F2C04c1C662D17d4577e); // https://app.roninchain.com/address/0x7e73630f81647bcfd7b1f2c04c1c662d17d4577e
  address _wbtcMainchainToken = address(0x2260FAC5E5542a773Aa44fBCfeDf7C193bc2C599); // https://etherscan.io/token/0x2260fac5e5542a773aa44fbcfedf7c193bc2c599

  // The decimal of WBTC token is 18
  uint256 _wbtcHighTierThreshold = 17 ether;
  uint256 _wbtcLockedThreshold = 34 ether;
  uint256 _wbtcDailyWithdrawalLimit = 42 ether;
  uint256 _wbtcMinThreshold = 0.000167 ether;

  // The MAX_PERCENTAGE is 100_0000
  uint256 _wbtcUnlockFeePercentages = 10; // 0.001%. Max percentage is 1e6 so 10 is 0.001% (`10 / 1e6 = 0.001 * 100`)
}
