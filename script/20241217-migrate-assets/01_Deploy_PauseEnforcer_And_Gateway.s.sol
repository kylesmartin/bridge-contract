// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import { Migrate_Assets_Base } from "script/20241217-migrate-assets/Migrate_Assets_Base.s.sol";
import { LibCompanionNetwork } from "script/shared/libraries/LibCompanionNetwork.sol";
import { Contract } from "script/utils/Contract.sol";
import { Network } from "script/utils/Network.sol";

import { TNetwork } from "@fdk/types/TNetwork.sol";
import { DefaultNetwork } from "@fdk/utils/DefaultNetwork.sol";

contract Migration_01_Deploy_PauseEnforcer_And_Gateway is Migrate_Assets_Base {
  using LibCompanionNetwork for *;

  address private _ronPauseEnforcer;
  address private _ronGatewayV3Logic;

  address private _ethPauseEnforcer;
  address private _ethGatewayV3Logic;

  function run() public virtual {
    _ronPauseEnforcer = _deployImmutable(Contract.RoninPauseEnforcer.key());
    _ronGatewayV3Logic = _deployLogic(Contract.RoninGatewayV3.key());

    (, TNetwork companionNetwork) = network().companionNetworkData();

    (TNetwork prvNetwork, uint256 prvForkId) = switchTo(companionNetwork);

    _ethPauseEnforcer = _deployImmutable(Contract.MainchainPauseEnforcer.key());
    _ethGatewayV3Logic = _deployLogic(Contract.MainchainGatewayV3.key());

    switchBack(prvNetwork, prvForkId);
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
