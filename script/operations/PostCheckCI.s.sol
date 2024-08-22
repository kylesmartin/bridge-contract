// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import { console } from "forge-std/console.sol";
import { GatewayV3 } from "@ronin/contracts/extensions/GatewayV3.sol";
import { TransparentUpgradeableProxy } from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import { DefaultNetwork } from "@fdk/utils/DefaultNetwork.sol";
import { LibProxy } from "@fdk/libraries/LibProxy.sol";
import { TNetwork } from "@fdk/types/TNetwork.sol";
import { Migration } from "script/Migration.s.sol";
import { Contract } from "script/utils/Contract.sol";
import { LibCompanionNetwork } from "script/shared/libraries/LibCompanionNetwork.sol";
import { IPauseTarget } from "@ronin/contracts/interfaces/IPauseTarget.sol";

contract PostCheckCI is Migration {
  using LibProxy for *;
  using LibCompanionNetwork for *;

  function run() external onlyOn(DefaultNetwork.RoninMainnet.key()) {
    address payable ronBM = loadContract(Contract.RoninBridgeManager.key());
    address payable ronGW = loadContract(Contract.RoninGatewayV3.key());
    _cheatChangePAIfNotSelf(ronBM);
    _cheatUnpauseIfPaused(ronGW);

    TNetwork currNetwork = network();
    TNetwork companionNetwork = currNetwork.companionNetwork();

    (, uint256 prevForkId) = switchTo(companionNetwork);
    address payable ethBM = loadContract(Contract.MainchainBridgeManager.key());
    address payable ethGW = loadContract(Contract.MainchainGatewayV3.key());
    _cheatChangePAIfNotSelf(ethBM);
    _cheatUnpauseIfPaused(ethGW);

    switchBack(currNetwork, prevForkId);
  }

  function _cheatUnpauseIfPaused(address payable gw) internal {
    bool paused = IPauseTarget(gw).paused();
    if (paused) {
      address emergencyPauser = GatewayV3(gw).emergencyPauser();
      vm.prank(emergencyPauser);
      IPauseTarget(gw).unpause();

      assertFalse(IPauseTarget(gw).paused(), "GatewayV3 should not be paused after unpausing");
    }
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
