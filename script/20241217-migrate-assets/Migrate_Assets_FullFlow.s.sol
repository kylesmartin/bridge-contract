// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import { Migration } from "script/Migration.s.sol";

import { Migrate_Assets_Base } from "script/20241217-migrate-assets/Migrate_Assets_Base.s.sol";
import { Migration_01_Deploy_PauseEnforcer_And_Gateway } from "script/20241217-migrate-assets/01_Deploy_PauseEnforcer_And_Gateway.s.sol";
import { Migration_02_Propose_Upgrades } from "script/20241217-migrate-assets/02_Propose_Upgrades.s.sol";

contract Migrate_Assets_FullFlow is Migration_01_Deploy_PauseEnforcer_And_Gateway, Migration_02_Propose_Upgrades {
  function run() public virtual override(Migration_01_Deploy_PauseEnforcer_And_Gateway, Migration_02_Propose_Upgrades) {
    Migration_01_Deploy_PauseEnforcer_And_Gateway.run();
    Migration_02_Propose_Upgrades.run();
  }

  function _getRoninMigratorAddress()
    internal
    view
    virtual
    override(Migration_01_Deploy_PauseEnforcer_And_Gateway, Migration_02_Propose_Upgrades)
    returns (address)
  {
    return address(0x1);
  }

  function _getEthereumMigratorAddress()
    internal
    view
    virtual
    override(Migration_01_Deploy_PauseEnforcer_And_Gateway, Migration_02_Propose_Upgrades)
    returns (address)
  {
    return address(0x2);
  }

  function _getProposalProposer() internal view virtual override(Migrate_Assets_Base, Migration_02_Propose_Upgrades) returns (address) {
    return Migration_02_Propose_Upgrades._getProposalProposer();
  }

  function _getProposalExecutor() internal view virtual override(Migrate_Assets_Base, Migration_02_Propose_Upgrades) returns (address) {
    return address(0x4);
  }

  function _getRoninPauseEnforcer()
    internal
    view
    virtual
    override(Migration_01_Deploy_PauseEnforcer_And_Gateway, Migration_02_Propose_Upgrades)
    returns (address)
  {
    return Migration_01_Deploy_PauseEnforcer_And_Gateway._getRoninPauseEnforcer();
  }

  function _getEthereumPauseEnforcer()
    internal
    view
    virtual
    override(Migration_01_Deploy_PauseEnforcer_And_Gateway, Migration_02_Propose_Upgrades)
    returns (address)
  {
    return Migration_01_Deploy_PauseEnforcer_And_Gateway._getEthereumPauseEnforcer();
  }

  function _getRoninGatewayV3Logic()
    internal
    view
    virtual
    override(Migration_01_Deploy_PauseEnforcer_And_Gateway, Migration_02_Propose_Upgrades)
    returns (address)
  {
    return Migration_01_Deploy_PauseEnforcer_And_Gateway._getRoninGatewayV3Logic();
  }

  function _getMainchainGatewayV3Logic()
    internal
    view
    virtual
    override(Migration_01_Deploy_PauseEnforcer_And_Gateway, Migration_02_Propose_Upgrades)
    returns (address)
  {
    return Migration_01_Deploy_PauseEnforcer_And_Gateway._getMainchainGatewayV3Logic();
  }

  function _postCheck() internal virtual override(Migration, Migration_02_Propose_Upgrades) {
    Migration_02_Propose_Upgrades._postCheck();
  }
}
