// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import { Contract } from "../utils/Contract.sol";
import { Migration } from "../Migration.s.sol";

contract Migration__20240807_DeployMainchainGW is Migration {
  function run() public {
    _deployLogic(Contract.MainchainGatewayV3.key());
  }
}
