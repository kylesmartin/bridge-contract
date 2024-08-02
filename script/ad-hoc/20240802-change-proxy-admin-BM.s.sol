// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import { console } from "forge-std/console.sol";
import { Migration } from "script/Migration.s.sol";
import { Contract } from "script/utils/Contract.sol";
import { LibProxy } from "@fdk/libraries/LibProxy.sol";
import { TransparentUpgradeableProxy } from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";

contract MainchainTransferProxyAdminBridgeManager is Migration {
  using LibProxy for *;

  address internal constant ETH_MULTISIG = 0x51F6696Ae42C6C40CA9F5955EcA2aaaB1Cefb26e;

  function run() external {
    address mainchainBM = loadContract(Contract.MainchainBridgeManager.key());
    address currProxyAdmin = mainchainBM.getProxyAdmin();

    console.log("Mainchain BM", mainchainBM);
    console.log("Current PA", currProxyAdmin);

    vm.broadcast(currProxyAdmin);
    TransparentUpgradeableProxy(payable(mainchainBM)).changeAdmin(ETH_MULTISIG);

    address newProxyAdmin = mainchainBM.getProxyAdmin();
    assertEq(newProxyAdmin, ETH_MULTISIG, "New Proxy Admin");
    assertTrue(newProxyAdmin.code.length != 0, "Contain code at new proxy admin, probably multisig");

    console.log("New PA", newProxyAdmin);
  }
}