// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

contract Migration__20240409_GovernorsKey {
  function _loadGovernors() internal pure returns (address[] memory res) {
    res = new address[](1);

    res[0] = address(0xdeadbeef);
  }
}
