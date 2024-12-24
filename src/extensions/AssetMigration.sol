// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import { AccessControlEnumerable } from "@openzeppelin/contracts/access/AccessControlEnumerable.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { IERC721 } from "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import { HasProxyAdmin } from "src/extensions/collections/HasProxyAdmin.sol";

import { IWETH } from "src/interfaces/IWETH.sol";
import { ErrLengthMismatch, ErrEmptyArray } from "src/utils/CommonErrors.sol";

abstract contract AssetMigration is HasProxyAdmin, AccessControlEnumerable {
  using SafeERC20 for IERC20;

  /// @dev Error when the token is not whitelisted before
  error ErrNotWhitelistedToken(address token);
  /// @dev Error when the native token is whitelisted instead of the wrapped token
  error ErrWhitelistWrappedTokenInstead();

  /// @dev The native token indicator address
  address internal constant _NATIVE_TOKEN_INDICATOR = address(0);
  /// @dev The migrator role
  bytes32 internal constant _MIGRATOR_ROLE = keccak256("MIGRATOR_ROLE");

  /// @custom:storage-location erc7201:ronin.bridge.AssetMigration
  struct AssetMigrationStorage {
    // Whitelisted addresses
    mapping(address token => address whitelist) _whitelist;
  }

  /// @dev Emitted when recipients are whitelisted.
  event WhitelistUpdated(address indexed by, address[] tokens, address[] recipients);

  /**
   * @dev Modifier to check if `a` and `b` have the same length and are not empty.
   */
  modifier validInput(uint256[] memory a, uint256[] memory b) {
    _requireValidInput(a, b);
    _;
  }

  /**
   * @dev Returns the wrapped native token.
   * - For `MainchainGatewayV3`, it MUST return the WETH token.
   */
  function wrappedNativeToken() external view virtual returns (IWETH) {
    revert("Not implemented");
  }

  /**
   * @dev Migrates the given tokens to the specified addresses.
   *
   * When the token is the native (i.e RON or ETH), it will be wrapped (i.e WRON, WETH).
   *
   * Requirements:
   * - The caller must be the migrator.
   * - The length of the arrays must be the same.
   * - The length of the arrays must not be zero.
   */
  function migrateERC20(address[] calldata tokens, uint256[] calldata amounts) external onlyRole(_MIGRATOR_ROLE) validInput(_toUint256s(tokens), amounts) {
    uint256 length = amounts.length;
    IERC20 token;

    for (uint256 i; i < length; ++i) {
      token = IERC20(tokens[i]);

      if (address(token) == address(_NATIVE_TOKEN_INDICATOR)) {
        token = _wrap(amounts[i]);
      }

      address recipient = _getRecipient(address(token));
      token.safeTransfer(recipient, amounts[i]);
    }
  }

  /**
   * @dev Migrates the given ERC721 tokens to the specified addresses.
   *
   * Requirements:
   * - The caller must be the migrator.
   * - The length of the arrays must be the same.
   * - The length of the arrays must not be zero.
   * - If `recipient` is not whitelisted and not inherit from the `ERC721Receiver` interface, it will revert.
   */
  function migrateERC721(address[] calldata tokens, uint256[] calldata ids) external onlyRole(_MIGRATOR_ROLE) validInput(_toUint256s(tokens), ids) {
    uint256 length = tokens.length;

    for (uint256 i; i < length; ++i) {
      address recipient = _getRecipient(tokens[i]);
      IERC721(tokens[i]).safeTransferFrom(address(this), recipient, ids[i]);
    }
  }

  /**
   * @dev Whitelists the recipients for the given tokens.
   *
   * Requirements:
   * - Must go through proposal via `BridgeManager`.
   */
  function whitelist(address[] calldata tokens, address[] calldata recipients) external onlyProxyAdmin validInput(_toUint256s(recipients), _toUint256s(tokens)) {
    _whitelist(recipients, tokens);
  }

  /**
   * @dev Get all whitelisted addresses for the given tokens.
   */
  function getWhitelistedAddresses(
    address[] calldata tokens
  ) external view returns (address[] memory whitelisteds) {
    AssetMigrationStorage storage $ = _getAssetMigration();

    uint256 length = tokens.length;
    whitelisteds = new address[](length);

    for (uint256 i; i < length; ++i) {
      whitelisteds[i] = $._whitelist[tokens[i]];
    }
  }

  /**
   * @dev Returns the pointer of the AssetMigrationStorage struct.
   */
  function _getAssetMigration() private pure returns (AssetMigrationStorage storage $) {
    // value is equal to keccak256(abi.encode(uint256(keccak256("ronin.bridge.AssetMigration")) - 1)) &
    // ~bytes32(uint256(0xff))
    bytes32 storageLoc = 0x06e9d321f1aa72738d882c53ba334d30578ba3db2fbd2df66a07059b7abc9900;

    assembly ("memory-safe") {
      $.slot := storageLoc
    }
  }

  /**
   * @dev Converts the native token to its wrapped version.
   */
  function _wrap(
    uint256 amount
  ) internal returns (IERC20) {
    IWETH w = this.wrappedNativeToken();
    w.deposit{ value: amount }();

    return IERC20(address(w));
  }

  /**
   * @dev Sets the whitelist status of the recipients.
   * This function does not revert when the recipient is already whitelisted or not.
   * if `recipient` is zero address, it will remove the whitelist status.
   */
  function _whitelist(address[] calldata tokens, address[] calldata recipients) internal {
    AssetMigrationStorage storage $ = _getAssetMigration();
    uint256 length = recipients.length;

    for (uint256 i; i < length; ++i) {
      require(tokens[i] != _NATIVE_TOKEN_INDICATOR, ErrWhitelistWrappedTokenInstead());

      $._whitelist[tokens[i]] = recipients[i];
    }

    emit WhitelistUpdated(msg.sender, tokens, recipients);
  }

  /**
   * @dev Throws if the recipient is not whitelisted.
   * Returns the recipient address.
   */
  function _getRecipient(
    address token
  ) internal view returns (address recipient) {
    recipient = _getAssetMigration()._whitelist[token];
    require(recipient != address(0x0), ErrNotWhitelistedToken(token));
  }

  /**
   * @dev Throws if `a` and `b` have different lengths or are empty.
   */
  function _requireValidInput(uint256[] memory a, uint256[] memory b) internal pure {
    require(a.length != 0, ErrEmptyArray());
    require(a.length == b.length, ErrLengthMismatch(msg.sig));
  }

  function _toUint256s(
    address[] memory a
  ) internal pure returns (uint256[] memory b) {
    assembly ("memory-safe") {
      b := a
    }
  }
}
