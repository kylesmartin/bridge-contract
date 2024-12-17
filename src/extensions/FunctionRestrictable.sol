// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import { TokenStandard } from "src/libraries/LibTokenInfo.sol";
import { ErrInvalidStorageLocation } from "src/utils/CommonErrors.sol";

abstract contract FunctionRestrictable {
  /// @custom:storage-location erc7201:ronin.bridge.FunctionRestrictable
  struct FunctionalRestrictableStorage {
    mapping(bytes4 fnSig => uint8 bitmap) _stdBitmap;
  }

  /// @dev Emit when a function is paused.
  event Restricted(address indexed by, bytes4 indexed fnSig, uint8 stdBitmap);
  /// @dev Emit when a function is unpaused.
  event UnRestricted(address indexed by, bytes4 indexed fnSig);

  /**
   * @dev Modifier to check if the caller is authorized.
   */
  modifier onlyAuth() {
    _requireAuth();
    _;
  }

  /**
   * @dev Modifier to check if the function signature does not collide with reserved signatures.
   */
  modifier validSig(
    bytes4 sig
  ) {
    _requireValidSig(sig);
    _;
  }

  /**
   * @dev Pause a function.
   *
   * Requirement:
   *
   * @param fnSig The function signature to pause.
   *
   * Emits a {Restricted} event.
   */
  function restrict(bytes4 fnSig, uint8 standardBitMap) external onlyAuth validSig(fnSig) {
    _restrict(fnSig, standardBitMap);
  }

  function restricted(bytes4 fnSig, TokenStandard standard) public view returns (bool yes) {
    yes = _getFunctionalRestrictable()._stdBitmap[fnSig] & (1 << uint8(standard)) != 0;
  }

  /**
   * @dev Restrict a specific function with standard bitmap.
   *
   * Requirement:
   */
  function _restrict(bytes4 fnSig, uint8 standardBitMap) internal {
    _getFunctionalRestrictable()._stdBitmap[fnSig] = standardBitMap;

    if (standardBitMap == 0) {
      emit UnRestricted(msg.sender, fnSig);
    } else {
      emit Restricted(msg.sender, fnSig, standardBitMap);
    }
  }

  function _requireAuth() internal virtual;

  function _requireNotRestricted(bytes4 fnSig, TokenStandard standard) internal view {
    require(!restricted(fnSig, standard), "FunctionRestrictable: restricted");
  }

  function _toBitmap(
    TokenStandard standard
  ) internal pure returns (uint8) {
    return uint8(1 << uint8(standard));
  }

  /**
   * @dev Throws if the function signature is collided with reserved signatures for `Pausable` or `FunctionRestrictable`.
   */
  function _requireValidSig(
    bytes4 sig
  ) private pure {
    bool valid = true;

    if (sig == FunctionRestrictable.restrict.selector) valid = false;
    if (sig == bytes4(abi.encodeWithSignature("restricted(bytes4,uint8)"))) valid = false;
    if (sig == bytes4(abi.encodeWithSignature("pause()"))) valid = false;
    if (sig == bytes4(abi.encodeWithSignature("paused()"))) valid = false;
    if (sig == bytes4(abi.encodeWithSignature("unpause()"))) valid = false;

    require(valid, "FunctionRestrictable: invalid sig");
  }

  /**
   * @dev Returns the storage pointer of the FunctionalRestrictableStorage struct.
   */
  function _getFunctionalRestrictable() private pure returns (FunctionalRestrictableStorage storage $) {
    bytes32 loc = _$$FunctionalRestrictableLocation();
    require(loc != 0, ErrInvalidStorageLocation());

    assembly ("memory-safe") {
      $.slot := loc
    }
  }

  /**
   * @dev Returns the custom storage location of the FunctionalRestrictableStorage struct.
   */
  function _$$FunctionalRestrictableLocation() internal pure returns (bytes32 storageLoc) {
    // value is equal to keccak256(abi.encode(uint256(keccak256("ronin.bridge.FunctionRestrictable")) - 1)) &
    // ~bytes32(uint256(0xff))
    storageLoc = 0xa7959878b25ffc8190f7b5440888c97e9a819bbb4963604c213ae021e3145700;
  }
}
