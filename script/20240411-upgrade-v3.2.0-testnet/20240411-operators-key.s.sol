// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

contract Migration__20240409_GovernorsKey {
  function _loadGovernors() internal pure returns (address[] memory res) {
    res = new address[](4);

    res[3] = 0xd24D87DDc1917165435b306aAC68D99e0F49A3Fa;
    res[2] = 0xb033ba62EC622dC54D0ABFE0254e79692147CA26;
    res[0] = 0x087D08e3ba42e64E3948962dd1371F906D1278b9;
    res[1] = 0x52ec2e6BBcE45AfFF8955Da6410bb13812F4289F;
  }
}
