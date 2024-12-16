// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import { Pausable } from "@openzeppelin/contracts/security/Pausable.sol";

import { ErrInvalidStorageLocation } from "src/utils/CommonErrors.sol";

abstract contract FunctionalPausable is Pausable {
  /// @custom:storage-location erc7201:ronin.bridge.FunctionalPausable
  struct FunctionPauseStorage {
    mapping(bytes4 fnSig => bool isPaused) _fnPaused;
  }

  /// @dev Emit when a function is paused.
  event Paused(address indexed by, bytes4 indexed fnSig);
  /// @dev Emit when a function is unpaused.
  event Unpaused(address indexed by, bytes4 indexed fnSig);

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
   * - The function must not be paused before or not globally paused.
   *
   * @param fnSig The function signature to pause.
   *
   * Emits a {Paused} event.
   */
  function pauseFn(
    bytes4 fnSig
  ) external onlyAuth validSig(fnSig) {
    _pause(fnSig);
  }

  /**
   * @dev Unpause a function.
   *
   * Requirement:
   * - The function must be paused before and not globally paused.
   *
   * @param fnSig The function signature to unpause.
   *
   * Emits a {Unpaused} event.
   */
  function unpauseFn(
    bytes4 fnSig
  ) external onlyAuth validSig(fnSig) {
    _unpause(fnSig);
  }

  /**
   * @dev
   * If interacted externally, return true if globally paused.
   * If interacted internally, return true if globally paused or the function signature for given context is paused.
   */
  function paused() public view virtual override returns (bool) {
    return paused(msg.sig);
  }

  /**
   * @dev Return true if globally paused or the function signature for given context is paused.
   */
  function paused(
    bytes4 fnSig
  ) public view returns (bool) {
    return Pausable.paused() || _getFunctionalPause()._fnPaused[fnSig];
  }

  /**
   * @dev Pause a specific function.
   *
   * Requirement:
   * - The function must not be paused before or not globally paused.
   */
  function _pause(
    bytes4 fnSig
  ) internal {
    _requireNotPaused(fnSig);
    _getFunctionalPause()._fnPaused[fnSig] = true;
    emit Paused(msg.sender, fnSig);
  }

  /**
   * @dev Unpause a specific function.
   *
   * Requirement:
   * - The function must be paused before and not globally paused.
   */
  function _unpause(
    bytes4 fnSig
  ) internal {
    _requirePaused(fnSig);
    _getFunctionalPause()._fnPaused[fnSig] = false;
    emit Unpaused(msg.sender, fnSig);
  }

  function _requireAuth() internal virtual;

  /**
   * @dev Throws if the function signature is paused or globally paused.
   */
  function _requireNotPaused(
    bytes4 fnSig
  ) internal view {
    require(!paused(fnSig), "FunctionalPausable: paused");
  }

  /**
   * @dev Throws if the function signature is paused.
   */
  function _requirePaused(
    bytes4 fnSig
  ) internal view {
    require(paused(fnSig), "FunctionalPausable: not paused");
  }

  /**
   * @dev Throws if the function signature is collided with reserved signatures for `Pausable` or `FunctionalPausable`.
   */
  function _requireValidSig(
    bytes4 sig
  ) private pure {
    bool valid = true;

    if (sig == Pausable.paused.selector) valid = false;
    if (sig == FunctionalPausable.pauseFn.selector) valid = false;
    if (sig == FunctionalPausable.unpauseFn.selector) valid = false;
    if (sig == bytes4(abi.encodeWithSignature("paused(bytes4)"))) valid = false;
    if (sig == bytes4(abi.encodeWithSignature("pause()"))) valid = false;
    if (sig == bytes4(abi.encodeWithSignature("unpause()"))) valid = false;

    require(valid, "FunctionalPausable: invalid sig");
  }

  /**
   * @dev Returns the storage pointer of the FunctionPauseStorage struct.
   */
  function _getFunctionalPause() private pure returns (FunctionPauseStorage storage $) {
    bytes32 loc = _$$FunctionalPauseLocation();
    require(loc != 0, ErrInvalidStorageLocation());

    assembly ("memory-safe") {
      $.slot := loc
    }
  }

  /**
   * @dev Returns the custom storage location of the FunctionPauseStorage struct.
   */
  function _$$FunctionalPauseLocation() internal pure returns (bytes32 storageLoc) {
    // value is equal to keccak256(abi.encode(uint256(keccak256("ronin.bridge.FunctionalPausable")) - 1)) &
    // ~bytes32(uint256(0xff))
    storageLoc = 0xc8a6530fff17c51a56dcc5c75875263c1a8e215f37c955e38b1e858bdde4b900;
  }
}
