// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

contract Migration__MapToken_WBTC_Threshold {
  address _wbtcRoninToken = address(0xdeadbeef); // TODO: replace by real WBTC token address
  address _wbtcMainchainToken = address(0x3429d03c6F7521AeC737a0BBF2E5ddcef2C3Ae31);

  // The decimal of WBTC token is 18
  uint256 _wbtcHighTierThreshold = 17 ether;
  uint256 _wbtcLockedThreshold = 34 ether;
  uint256 _wbtcDailyWithdrawalLimit = 42 ether;
  uint256 _wbtcMinThreshold = 0.000167 ether;

  // The MAX_PERCENTAGE is 100_0000
  uint256 _wbtcUnlockFeePercentages = 10; // 0.001%. Max percentage is 1e6 so 10 is 0.001% (`10 / 1e6 = 0.001 * 100`)
}