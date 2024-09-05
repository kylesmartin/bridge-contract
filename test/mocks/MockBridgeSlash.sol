// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.8.17 <0.9.0;

import { BridgeSlash } from "@ronin/contracts/ronin/gateway/BridgeSlash.sol";

contract MockBridgeSlash is BridgeSlash {
  mapping(address => uint256) internal _slashMap;

  function calcSlashUntilPeriod(Tier tier, uint256 period, uint256 slashUntilPeriod) external pure returns (uint256 newSlashUntilPeriod) {
    newSlashUntilPeriod = _calcSlashUntilPeriod(tier, period, slashUntilPeriod, _getPenaltyDurations());
  }

  function isSlashDurationMetRemovalThreshold(uint256 slashUntilPeriod, uint256 period) external pure returns (bool) {
    return _isSlashDurationMetRemovalThreshold(slashUntilPeriod, period);
  }

  function getSlashUntilPeriodOf(address[] calldata operators) external view virtual override returns (uint256[] memory untilPeriods) {
    untilPeriods = new uint256[](operators.length);
    for (uint i; i < operators.length; i++) {
      untilPeriods[i] = _slashMap[operators[i]];
    }
  }

  function cheat_setSlash(address[] calldata operators, uint256[] calldata untilPeriods) external {
    require(operators.length == untilPeriods.length, "invalid length");

    for (uint i; i < operators.length; i++) {
      _slashMap[operators[i]] = untilPeriods[i];
    }
  }
}
