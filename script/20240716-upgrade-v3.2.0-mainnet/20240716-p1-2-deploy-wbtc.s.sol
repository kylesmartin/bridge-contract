// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import { ISharedArgument } from "../interfaces/ISharedArgument.sol";
import { Migration } from "../Migration.s.sol";
import { Contract } from "../utils/Contract.sol";
import { WBTC } from "src/tokens/erc20/WBTC.sol";

import "./20240716-deploy-wbtc-helper.s.sol";

contract Migration__20240716_P1_1_DeployWBTC is Migration__20240716_DeployWBTC_Helper {
  function _defaultArguments() internal virtual override returns (bytes memory) {
    ISharedArgument.WBTCParam memory param = config.sharedArguments().wbtc;
    return abi.encode(param.gateway, param.pauser);
  }

  function run() public returns (WBTC instance) {
    _deployWBTC();
  }
}
