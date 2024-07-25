// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/presets/ERC20PresetMinterPauser.sol";

contract WBTC is ERC20PresetMinterPauser {
  address public immutable GATEWAY_ADDRESS;

  constructor(address gateway, address pauser) ERC20PresetMinterPauser("Wrapped Bitcoin", "WBTC") {
    _setupRole(DEFAULT_ADMIN_ROLE, pauser);
    _setupRole(PAUSER_ROLE, pauser);

    GATEWAY_ADDRESS = gateway;
    _setupRole(MINTER_ROLE, gateway);

    _revokeRole(DEFAULT_ADMIN_ROLE, _msgSender());
    _revokeRole(MINTER_ROLE, _msgSender());
    _revokeRole(PAUSER_ROLE, _msgSender());
  }

  function _beforeTokenTransfer(address from, address to, uint256 amount) internal override(ERC20PresetMinterPauser) {
    if (to == address(0)) {
      if (_msgSender() != GATEWAY_ADDRESS) {
        revert("WBTC: only gateway can burn tokens");
      }
    }

    super._beforeTokenTransfer(from, to, amount);
  }
}
