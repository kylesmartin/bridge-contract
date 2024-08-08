// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import { console } from "forge-std/console.sol";
import { ISharedArgument } from "../interfaces/ISharedArgument.sol";
import { Migration } from "../Migration.s.sol";
import { Contract } from "../utils/Contract.sol";
import { WBTC } from "src/tokens/erc20/WBTC.sol";

abstract contract Migration__20240716_DeployWBTC_Helper is Migration {
  function _deployWBTC() internal {
    WBTC instance = WBTC(_deployImmutable(Contract.WBTC.key()));
    console.log("WBTC deployed at:", address(instance));
  }
}
