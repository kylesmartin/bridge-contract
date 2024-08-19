// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import { console } from "forge-std/console.sol";
import { TransparentUpgradeableProxy } from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import { DefaultNetwork } from "@fdk/utils/DefaultNetwork.sol";
import { LibProxy } from "@fdk/libraries/LibProxy.sol";
import { TNetwork } from "@fdk/types/TNetwork.sol";
import { Migration } from "./Migration.s.sol";
import { Contract } from "./utils/Contract.sol";
import { LibCompanionNetwork } from "./shared/libraries/LibCompanionNetwork.sol";

contract PostCheckCI is Migration {
  using LibProxy for *;
  using LibCompanionNetwork for *;

  function run() external onlyOn(DefaultNetwork.RoninMainnet.key()) {
    address payable ronBM = loadContract(Contract.RoninBridgeManager.key());
    _cheatChangePAIfNotSelf(ronBM);

    TNetwork currNetwork = network();
    TNetwork companionNetwork = currNetwork.companionNetwork();

    (, uint256 prevForkId) = switchTo(companionNetwork);
    address payable ethBM = loadContract(Contract.MainchainBridgeManager.key());
    _cheatChangePAIfNotSelf(ethBM);

    switchBack(currNetwork, prevForkId);
  }

  function _cheatChangePAIfNotSelf(address payable proxy) private {
    address payable pa = proxy.getProxyAdmin();
    if (pa != proxy) {
      console.log("Cheat changing proxy admin of %s from %s to %s", vm.getLabel(proxy), pa, proxy);
      vm.prank(pa);
      TransparentUpgradeableProxy(proxy).changeAdmin(proxy);
    }
  }
}
