// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

contract Migration__20240619_GovernorsKey {
  function _loadGovernors() internal pure returns (address[] memory res) {
    res = new address[](4);

    res[0] = address(0x0);
    res[1] = address(0x0);
    res[2] = address(0x0);
    res[3] = address(0x0);
  }
}
