// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

contract Migration__Governors_Config {
  address[] internal governors = new address[](4);
  uint256[] internal governorPks = new uint256[](4);

  constructor() {
    // TODO: replace by address of the testnet governors
    governors[3] = 0xd24D87DDc1917165435b306aAC68D99e0F49A3Fa;
    governors[2] = 0xb033ba62EC622dC54D0ABFE0254e79692147CA26;
    governors[0] = 0x087D08e3ba42e64E3948962dd1371F906D1278b9;
    governors[1] = 0x52ec2e6BBcE45AfFF8955Da6410bb13812F4289F;
    // TODO: replace by private key of the testnet governors
    governorPks[3] = 0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80;
    governorPks[2] = 0x7c852118294e51e653712a81e05800f419141751be58f605c371e15141b007a6;
    governorPks[0] = 0x5de4111afa1a4b94908f83103eb1f1706367c2e68ca870fc3fb9a804cdab365a;
    governorPks[1] = 0x59c6995e998f97a5a0044966f0945389dc9e86dae88c7a8412f4603b6b78690d;
  }
}
