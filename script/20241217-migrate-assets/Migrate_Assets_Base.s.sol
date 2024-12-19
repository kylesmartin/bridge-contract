// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import { Migration } from "script/Migration.s.sol";

abstract contract Migrate_Assets_Base is Migration {
  function _getProposalExecutor() internal view virtual returns (address) {
    return address(0);
  }

  function _getProposalProposer() internal view virtual returns (address) {
    return address(0);
  }

  function _getRoninMigratorAddress() internal view virtual returns (address);

  function _getEthereumMigratorAddress() internal view virtual returns (address);

  function _getRoninGatewayV3Logic() internal view virtual returns (address);

  function _getMainchainGatewayV3Logic() internal view virtual returns (address);

  function _getRoninPauseEnforcer() internal view virtual returns (address);

  function _getEthereumPauseEnforcer() internal view virtual returns (address);
}
