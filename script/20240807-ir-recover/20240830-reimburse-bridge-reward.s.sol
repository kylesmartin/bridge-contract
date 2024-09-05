// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import { console } from "forge-std/console.sol";
import { DefaultNetwork } from "@fdk/utils/DefaultNetwork.sol";
import { IBridgeReward } from "@ronin/contracts/interfaces/bridge/IBridgeReward.sol";

import { Contract } from "../utils/Contract.sol";
import { Migration } from "../Migration.s.sol";

interface IRoninValidatorSet {
  function currentPeriod() external view returns (uint);
}

contract Migration__20240830_Reimburse_Bridge_Reward is Migration {
  IBridgeReward _bridgeReward;
  IRoninValidatorSet _roninValidatorSet;
  address _smOperator;

  function run() public virtual onlyOn(DefaultNetwork.RoninMainnet.key()) {
    _bridgeReward = IBridgeReward(loadContract(Contract.BridgeReward.key()));
    _roninValidatorSet = IRoninValidatorSet(0x617c5d73662282EA7FfD231E020eCa6D2B0D552f);
    _smOperator = 0x4b3844A29CFA5824F53e2137Edb6dc2b54501BeA;

    uint lastRewardedPeriod = _bridgeReward.getLatestRewardedPeriod();
    uint currentPeriod = _roninValidatorSet.currentPeriod();

    console.log("Last rewarded period:", lastRewardedPeriod);
    console.log("Current period:", currentPeriod);

    vm.startBroadcast(_smOperator);
    _bridgeReward.syncRewardManual(currentPeriod - lastRewardedPeriod - 1);
    vm.stopBroadcast();
  }
}
