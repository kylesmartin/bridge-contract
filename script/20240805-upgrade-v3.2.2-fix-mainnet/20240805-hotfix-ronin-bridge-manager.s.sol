// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import { console } from "forge-std/console.sol";
import { Migration } from "script/Migration.s.sol";
import { Contract } from "script/utils/Contract.sol";
import { LibProxy } from "@fdk/libraries/LibProxy.sol";
import { cheatBroadcast } from "@fdk/utils/Helpers.sol";
import { RoninBridgeManager } from "@ronin/contracts/ronin/gateway/RoninBridgeManager.sol";
import { TransparentUpgradeableProxy } from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";

contract Migration__20240805_HotFix_RoninBridgeManager is Migration {
  using LibProxy for *;

  function run() external {
    address roninBM = loadContract(Contract.RoninBridgeManager.key());
    address proxyAdmin = roninBM.getProxyAdmin();
    address bridgeSlash = loadContract(Contract.BridgeSlash.key());
    address roninGW = loadContract(Contract.RoninGatewayV3.key());
    // Cheat set admin slot to current bm
    vm.store(roninGW, LibProxy.ADMIN_SLOT, bytes32(uint256(uint160(roninBM))));
    // Cheat set impl slot to new bridge slash logic
    vm.store(bridgeSlash, LibProxy.IMPLEMENTATION_SLOT, bytes32(uint256(uint160(0xfc274EC92bBb1A1472884558d1B5CaaC6F8220Ee))));

    console.log("Proxy Admin", proxyAdmin);

    address prevImpl = roninBM.getProxyImplementation();

    console.log("Prev Impl", prevImpl);

    address hotfixImpl = _deployLogic(Contract.RoninBridgeManager.key());

    console.log("Hotfix Impl", hotfixImpl);

    cheatBroadcast(
      proxyAdmin,
      roninBM,
      0,
      abi.encodeCall(
        TransparentUpgradeableProxy.upgradeToAndCall,
        (hotfixImpl, abi.encodeCall(RoninBridgeManager.hotfix__mapToken_setMinimumThresholds_registerCallbacks, ()))
      )
    );

    cheatBroadcast(proxyAdmin, roninBM, 0, abi.encodeCall(TransparentUpgradeableProxy.upgradeTo, (prevImpl)));
  }
}
