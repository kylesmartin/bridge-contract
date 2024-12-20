// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import { AccessControlEnumerable } from "@openzeppelin/contracts/access/AccessControlEnumerable.sol";

import { PauseEnforcer } from "src/ronin/gateway/PauseEnforcer.sol";
import { IPauseTarget } from "src/interfaces/IPauseTarget.sol";

import { Migrate_Assets_Base } from "script/20241217-migrate-assets/Migrate_Assets_Base.s.sol";
import { LibCompanionNetwork } from "script/shared/libraries/LibCompanionNetwork.sol";
import { Contract } from "script/utils/Contract.sol";
import { Network } from "script/utils/Network.sol";

import { TNetwork } from "@fdk/types/TNetwork.sol";
import { DefaultNetwork } from "@fdk/utils/DefaultNetwork.sol";

contract Migration_01_Deploy_PauseEnforcer_And_Gateway is Migrate_Assets_Base {
  using LibCompanionNetwork for *;

  address private constant _PRV_RON_PAUSE_ENFORCER = 0x2367cD5468c2b3cD18aA74AdB7e14E43426aF837;
  address private constant _PRV_ETH_PAUSE_ENFORCER = 0xe514d9DEB7966c8BE0ca922de8a064264eA6bcd4;

  address private _ronPauseEnforcer;
  address private _ronGatewayV3Logic;

  address private _ethPauseEnforcer;
  address private _ethGatewayV3Logic;

  function run() public virtual {
    address ronGw = loadContract(Contract.RoninGatewayV3.key());
    (address[] memory admins, address[] memory sentries) = _getAllSentriesFromPreviousPauseEnforcer(_PRV_RON_PAUSE_ENFORCER);

    _ronPauseEnforcer = _deployImmutable(Contract.RoninPauseEnforcer.key(), abi.encode(ronGw, admins, sentries));
    _ronGatewayV3Logic = _deployLogic(Contract.RoninGatewayV3.key());

    (, TNetwork companionNetwork) = network().companionNetworkData();

    (TNetwork prvNetwork, uint256 prvForkId) = switchTo(companionNetwork);

    address ethGw = loadContract(Contract.MainchainGatewayV3.key());
    (admins, sentries) = _getAllSentriesFromPreviousPauseEnforcer(_PRV_ETH_PAUSE_ENFORCER);

    _ethPauseEnforcer = _deployImmutable(Contract.MainchainPauseEnforcer.key(), abi.encode(ethGw, admins, sentries));
    _ethGatewayV3Logic = _deployLogic(Contract.MainchainGatewayV3.key());

    switchBack(prvNetwork, prvForkId);
  }

  function _getAllSentriesFromPreviousPauseEnforcer(
    address pauseEnforcer
  ) internal view returns (address[] memory admins, address[] memory sentries) {
    admins = new address[](AccessControlEnumerable(pauseEnforcer).getRoleMemberCount(0));
    sentries = new address[](AccessControlEnumerable(pauseEnforcer).getRoleMemberCount(keccak256("SENTRY_ROLE")));

    for (uint256 i; i < admins.length; ++i) {
      admins[i] = AccessControlEnumerable(pauseEnforcer).getRoleMember(0, i);
    }

    for (uint256 i; i < sentries.length; ++i) {
      sentries[i] = AccessControlEnumerable(pauseEnforcer).getRoleMember(keccak256("SENTRY_ROLE"), i);
    }
  }

  function _getRoninMigratorAddress() internal view virtual override returns (address) {
    revert("Not implemented");
  }

  function _getEthereumMigratorAddress() internal view virtual override returns (address) {
    revert("Not implemented");
  }

  function _getRoninGatewayV3Logic() internal view virtual override returns (address) {
    return _ronGatewayV3Logic;
  }

  function _getMainchainGatewayV3Logic() internal view virtual override returns (address) {
    return _ethGatewayV3Logic;
  }

  function _getRoninPauseEnforcer() internal view virtual override returns (address) {
    return _ronPauseEnforcer;
  }

  function _getEthereumPauseEnforcer() internal view virtual override returns (address) {
    return _ethPauseEnforcer;
  }
}
